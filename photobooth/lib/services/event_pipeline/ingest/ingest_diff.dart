import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'ingest_source.dart';

/// One folder found on a card, with how many importable images it holds.
///
/// Surfaced so the operator can widen a scan beyond `DCIM` when a photographer
/// has dropped files elsewhere, without making the common case dangerous.
class IngestFolderSummary {
  const IngestFolderSummary({
    required this.folder,
    required this.total,
    required this.newCount,
    required this.selectedByDefault,
  });

  final String folder;
  final int total;
  final int newCount;

  /// True when the folder is inside the configured scan roots.
  final bool selectedByDefault;
}

/// Outcome of diffing a card against the ledger, before any file is opened.
class IngestScanResult {
  const IngestScanResult({
    required this.newCandidates,
    required this.alreadyImported,
    required this.folders,
    required this.skippedRaw,
    required this.skippedOtherType,
    required this.outsideScanFolders,
  });

  /// Genuinely new, in the folders being scanned. Import order.
  final List<IngestCandidate> newCandidates;

  /// Matched the ledger on the tier-1 key — no file read was needed.
  final int alreadyImported;

  /// Every folder on the volume, whether scanned or not.
  final List<IngestFolderSummary> folders;

  /// RAW files passed over. Reported so a RAW-only card reads as "nothing
  /// importable, because RAW" rather than as a failed scan.
  final int skippedRaw;

  final int skippedOtherType;
  final int outsideScanFolders;

  bool get hasNew => newCandidates.isNotEmpty;

  /// True when the volume holds nothing importable at all — a fresh format.
  ///
  /// Distinct from "all already imported", which is what a rescan looks like.
  /// Reporting an empty card as "all 0 photos have been imported" is nonsense
  /// the operator cannot act on.
  bool get isEmptyCard =>
      newCandidates.isEmpty &&
      alreadyImported == 0 &&
      skippedRaw == 0 &&
      skippedOtherType == 0 &&
      outsideScanFolders == 0;

  /// True when a card holds only RAW — the case that most looks like a bug.
  bool get isRawOnly =>
      newCandidates.isEmpty && alreadyImported == 0 && skippedRaw > 0;

  /// Photos exist, but every one is outside the folders being scanned.
  ///
  /// The operator must still be offered the folder list here, or a photographer
  /// who dropped files outside DCIM has produced an unreachable card.
  bool get onlyOutsideScope =>
      newCandidates.isEmpty && alreadyImported == 0 && outsideScanFolders > 0;

  /// Folders the operator could add that are not already in scope.
  List<IngestFolderSummary> get widenableFolders =>
      [for (final f in folders) if (!f.selectedByDefault) f];
}

/// The tier-1 diff: metadata only, no file reads.
///
/// Tier 2 (the content key) needs bytes, so it lives in the ingest worker and
/// runs only over what survives this pass.
abstract final class IngestDiff {
  /// True when [folder] sits inside one of [scanFolders].
  ///
  /// Prefix comparison is case-insensitive and segment-aware, so `DCIM` matches
  /// `DCIM/100CANON` but not a sibling directory called `DCIMX`.
  static bool folderInScope(String folder, List<String> scanFolders) {
    if (scanFolders.isEmpty) return true;
    final f = folder.toLowerCase();
    for (final raw in scanFolders) {
      final root = raw.trim().toLowerCase().replaceAll(RegExp(r'^/+|/+$'), '');
      if (root.isEmpty) continue;
      if (f == root || f.startsWith('$root/')) return true;
    }
    return false;
  }

  /// Diffs [candidates] against the tier-1 keys already in the ledger.
  ///
  /// [knownSourceRefs] is the full set for this source, fetched in one query, so
  /// the comparison is a set lookup per candidate rather than a query per file.
  static IngestScanResult scan({
    required List<IngestCandidate> candidates,
    required Set<String> knownSourceRefs,
    required List<String> scanFolders,
    Set<String>? extraFolders,
  }) {
    final selected = <IngestCandidate>[];
    final folderTotals = <String, int>{};
    final folderNew = <String, int>{};
    final folderInDefault = <String, bool>{};
    var already = 0;
    var raw = 0;
    var otherType = 0;
    var outside = 0;

    for (final c in candidates) {
      if (!IngestMimeTypes.isImportable(c)) {
        if (IngestMimeTypes.isRaw(c)) {
          raw++;
        } else {
          otherType++;
        }
        continue;
      }

      final inDefault = folderInScope(c.folder, scanFolders);
      final included = inDefault || (extraFolders?.contains(c.folder) ?? false);
      final isNew = !knownSourceRefs.contains(c.sourceRef);

      folderTotals[c.folder] = (folderTotals[c.folder] ?? 0) + 1;
      folderInDefault[c.folder] = inDefault;
      if (isNew) folderNew[c.folder] = (folderNew[c.folder] ?? 0) + 1;

      if (!included) {
        outside++;
        continue;
      }
      if (isNew) {
        selected.add(c);
      } else {
        already++;
      }
    }

    // Oldest first, so an interrupted import leaves a contiguous prefix of the
    // shoot rather than a scattered subset.
    selected.sort((a, b) {
      final byTime = a.sortKey.compareTo(b.sortKey);
      if (byTime != 0) return byTime;
      return a.relativePath.compareTo(b.relativePath);
    });

    final folders = folderTotals.keys.toList()..sort();
    return IngestScanResult(
      newCandidates: selected,
      alreadyImported: already,
      skippedRaw: raw,
      skippedOtherType: otherType,
      outsideScanFolders: outside,
      folders: [
        for (final f in folders)
          IngestFolderSummary(
            folder: f,
            total: folderTotals[f] ?? 0,
            newCount: folderNew[f] ?? 0,
            selectedByDefault: folderInDefault[f] ?? false,
          ),
      ],
    );
  }
}

/// Tier-2 dedupe key: `sha1(size ‖ first 64 KiB ‖ last 64 KiB)`.
///
/// Deliberately not a full-file hash — at 6 MB × 3,000 frames that is minutes of
/// I/O for no extra safety. It exists to catch the same photograph arriving by
/// two routes (tethered during the shoot, then again from the card), which the
/// tier-1 path key cannot see.
abstract final class ContentKey {
  static const int sampleBytes = 64 * 1024;

  /// Computes the key by sampling through [read], which is given an offset and
  /// length and returns at most that many bytes.
  static Future<String> compute({
    required int sizeBytes,
    required Future<Uint8List> Function(int offset, int length) read,
  }) async {
    final head = await read(0, sampleBytes);
    final needsTail = sizeBytes > sampleBytes;
    final tail = needsTail
        ? await read(
            sizeBytes - sampleBytes < 0 ? 0 : sizeBytes - sampleBytes,
            sampleBytes,
          )
        : Uint8List(0);
    return fromSamples(sizeBytes: sizeBytes, head: head, tail: tail);
  }

  /// Pure form, for tests and for callers that already hold the samples.
  static String fromSamples({
    required int sizeBytes,
    required Uint8List head,
    required Uint8List tail,
  }) {
    // Size is folded in first so two files that share their sampled bytes but
    // differ in length cannot collide. At most 128 KiB plus a short prefix, so
    // one buffer is cheaper than a chunked conversion.
    final prefix = '$sizeBytes:'.codeUnits;
    final buffer = Uint8List(prefix.length + head.length + tail.length);
    buffer.setRange(0, prefix.length, prefix);
    buffer.setRange(prefix.length, prefix.length + head.length, head);
    buffer.setRange(prefix.length + head.length, buffer.length, tail);
    return sha1.convert(buffer).toString();
  }
}
