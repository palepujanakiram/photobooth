import 'dart:typed_data';

import '../../../models/event_pipeline/media_item.dart';
import 'event_storage_channel.dart';
import 'ingest_source.dart';

/// Reads a removable volume through MediaStore.
///
/// The mechanism the storage probe selected. Direct `File` access to a card is
/// denied to the app UID on API 30+ without the Play-restricted
/// MANAGE_EXTERNAL_STORAGE, but MediaStore indexes the card completely — and one
/// cursor returns the whole tier-1 dedupe key **plus** `datetaken`, so the diff
/// runs with zero file reads.
///
/// It also beats a SAF tree grant operationally: one runtime permission, granted
/// once, rather than an operator tap per unseen card.
class MediaStoreIngestSource implements IngestSource {
  MediaStoreIngestSource({
    required this.volume,
    required List<String> scanFolders,
    EventStorageChannel? channel,
  })  : _scanFolders = scanFolders,
        _channel = channel ?? EventStorageChannel();

  final ExternalVolume volume;
  final List<String> _scanFolders;
  final EventStorageChannel _channel;

  @override
  String get id => volume.uuid;

  @override
  String get label {
    final name = volume.description.trim();
    return name.isEmpty ? 'SD card (${volume.uuid})' : '$name (${volume.uuid})';
  }

  @override
  String get sourceKind => MediaSource.sdCard;

  @override
  Future<List<IngestCandidate>> listAll() async {
    final volumeName = volume.mediaStoreVolumeName;
    if (volumeName == null || volumeName.isEmpty) {
      // Mounted but not indexed. Returning empty is honest — the caller reports
      // it as "card not readable" rather than as an empty card.
      return const <IngestCandidate>[];
    }
    // Folder filtering happens natively so the cursor stays small, but the diff
    // still receives every candidate it is given and re-checks scope itself.
    final rows = await _channel.queryImages(
      volumeName: volumeName,
      folders: _scanFolders.isEmpty ? null : _scanFolders,
    );
    return [
      for (final row in rows)
        if (_toCandidate(row) case final c?) c,
    ];
  }

  IngestCandidate? _toCandidate(Map<Object?, Object?> row) {
    final relativePath = (row['relativePath'] ?? '').toString();
    final uri = (row['uri'] ?? '').toString();
    if (relativePath.isEmpty || uri.isEmpty) return null;
    final size = _int(row['sizeBytes']);
    if (size == null || size <= 0) return null;

    return IngestCandidate(
      sourceId: volume.uuid,
      relativePath: relativePath,
      displayName: (row['displayName'] ?? '').toString(),
      sizeBytes: size,
      // Already normalised to milliseconds natively — MediaStore stores
      // DATE_MODIFIED in seconds while DATE_TAKEN is in milliseconds.
      modifiedAtMs: _int(row['modifiedAtMs']) ?? 0,
      capturedAtMs: _int(row['capturedAtMs']),
      uri: uri,
      mimeType: row['mimeType'] as String?,
      width: _int(row['width']),
      height: _int(row['height']),
      orientation: _int(row['orientation']),
    );
  }

  static int? _int(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  @override
  Future<Uint8List> readRange(
    IngestCandidate candidate,
    int offset,
    int length,
  ) {
    return _channel.readRange(candidate.uri, offset, length);
  }
}

/// Scans a rescan until MediaStore has finished indexing a freshly inserted card.
///
/// **Required, not defensive.** A card mounts with zero rows and indexes over
/// time — measured at ~11 s for 261 files, so roughly two minutes for a
/// 3,000-frame card. Reading on the mount broadcast reports "0 new photos" on a
/// full card, which looks identical to a card that really is empty.
class MediaStoreSettleWatcher {
  MediaStoreSettleWatcher({
    this.pollInterval = const Duration(seconds: 2),
    this.stableReadsRequired = 3,
    this.timeout = const Duration(minutes: 5),
  });

  final Duration pollInterval;

  /// Consecutive identical counts before the index is considered complete.
  ///
  /// More than one because the scanner can plateau briefly mid-pass; a single
  /// repeat would call that settled and under-report the card.
  final int stableReadsRequired;

  final Duration timeout;

  /// Polls [count] until it stops changing, reporting progress as it goes.
  ///
  /// Returns the settled count, or the last seen count if [timeout] elapses —
  /// the caller shows a still-scanning indicator rather than pretending.
  Future<int> awaitSettled({
    required Future<int> Function() count,
    void Function(int current, bool settled)? onProgress,
    Future<void> Function(Duration)? delay,
  }) async {
    final sleep = delay ?? Future<void>.delayed;
    final deadline = DateTime.now().add(timeout);
    var last = -1;
    var stable = 0;

    while (DateTime.now().isBefore(deadline)) {
      final current = await count();
      if (current == last && current > 0) {
        stable++;
      } else {
        stable = 0;
      }
      last = current;
      final settled = stable >= stableReadsRequired - 1;
      onProgress?.call(current, settled);
      if (settled) return current;
      await sleep(pollInterval);
    }
    return last < 0 ? 0 : last;
  }
}
