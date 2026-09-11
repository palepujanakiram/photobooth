import 'dart:typed_data';

import '../../../models/event_pipeline/event_pipeline_settings.dart';
import '../../../models/event_pipeline/media_item.dart';
import '../../../models/event_pipeline/media_rendition.dart';
import '../../../utils/logger.dart';
import '../event_media_store.dart';
import '../event_pipeline_ledger.dart';
import 'image_downscaler.dart';
import 'ingest_diff.dart';
import 'ingest_failure.dart';
import 'ingest_source.dart';

/// Progress while an import runs, for the station's progress bar.
class IngestProgress {
  const IngestProgress({
    required this.done,
    required this.total,
    required this.imported,
    required this.duplicates,
    required this.failed,
  });

  final int done;
  final int total;
  final int imported;

  /// Caught by the content key after passing the path key — the same photo by a
  /// second route.
  final int duplicates;

  final int failed;
}

/// Outcome of one import run.
class IngestReport {
  const IngestReport({
    required this.imported,
    required this.duplicates,
    required this.failed,
    required this.mediaIds,
    this.stoppedEarly = false,
    this.stopReason,
  });

  final int imported;
  final int duplicates;
  final int failed;
  final List<String> mediaIds;

  /// True when the run halted before processing everything — a free-space floor,
  /// an operator cancel, or the card being pulled.
  final bool stoppedEarly;
  final String? stopReason;

  /// The reason reported when the source disappears mid-run.
  ///
  /// A constant because the operator screen keys its "reinsert it and scan
  /// again" message off it, and that message is only truthful because the
  /// rollback happened — see screens spec §9A.
  static const String cardRemovedReason = 'Card removed';

  bool get stoppedOnCardRemoval => stopReason == cardRemovedReason;

  int get processed => imported + duplicates + failed;
}

/// Scans a source, diffs it against the ledger, and imports what is new.
///
/// Each image is handled **one at a time**: sample, hash, downscale, write,
/// record. Nothing accumulates in memory, which is the fix for the existing
/// `pickFromCard` tray holding every file's bytes at once — 412 × 6 MB is
/// roughly 2.4 GB of heap and an OOM on the Amlogic box.
class IngestWorker {
  IngestWorker({
    required EventPipelineLedger ledger,
    required EventMediaStore mediaStore,
    required ImageDownscaler downscaler,
    int Function()? nowMs,
  })  : _ledger = ledger,
        _media = mediaStore,
        _downscaler = downscaler,
        _nowMs = nowMs ?? _defaultNowMs;

  final EventPipelineLedger _ledger;
  final EventMediaStore _media;
  final ImageDownscaler _downscaler;
  final int Function() _nowMs;

  static int _defaultNowMs() => DateTime.now().millisecondsSinceEpoch;

  /// Metadata-only pass. Cheap enough to run on every card insert.
  Future<IngestScanResult> scan(
    IngestSource source, {
    required List<String> scanFolders,
    Set<String>? extraFolders,
  }) async {
    final candidates = await source.listAll();
    final known = await _ledger.knownSourceRefs(source.sourceKind);
    return IngestDiff.scan(
      candidates: candidates,
      knownSourceRefs: known,
      scanFolders: scanFolders,
      extraFolders: extraFolders,
    );
  }

  /// Imports [candidates], writing a print-ready derivative for each.
  ///
  /// [shouldContinue] is checked before every image so an operator cancel or a
  /// free-space floor stops the run cleanly, leaving the ledger consistent —
  /// every item processed so far is fully recorded.
  Future<IngestReport> import(
    IngestSource source,
    List<IngestCandidate> candidates, {
    required EventPipelineSettings settings,
    String? eventId,
    void Function(IngestProgress progress)? onProgress,
    Future<String?> Function()? shouldContinue,
  }) async {
    var imported = 0;
    var duplicates = 0;
    var failed = 0;
    final mediaIds = <String>[];
    String? stopReason;

    for (var i = 0; i < candidates.length; i++) {
      stopReason = await shouldContinue?.call();
      if (stopReason != null) break;

      final outcome = await _importOne(
        source,
        candidates[i],
        settings: settings,
        eventId: eventId,
      );
      if (outcome.kind == _OutcomeKind.sourceGone) {
        // Not this photo's fault and not a per-item failure: its row is already
        // rolled back, and every remaining candidate would fail identically.
        // One clean stop beats grinding through 350 doomed items.
        stopReason = IngestReport.cardRemovedReason;
        break;
      }
      if (outcome.kind == _OutcomeKind.imported) {
        imported++;
        mediaIds.add(outcome.mediaId!);
      } else if (outcome.kind == _OutcomeKind.duplicate) {
        duplicates++;
      } else {
        failed++;
      }

      onProgress?.call(IngestProgress(
        done: i + 1,
        total: candidates.length,
        imported: imported,
        duplicates: duplicates,
        failed: failed,
      ));
    }

    return IngestReport(
      imported: imported,
      duplicates: duplicates,
      failed: failed,
      mediaIds: mediaIds,
      stoppedEarly: stopReason != null,
      stopReason: stopReason,
    );
  }

  Future<_Outcome> _importOne(
    IngestSource source,
    IngestCandidate candidate, {
    required EventPipelineSettings settings,
    String? eventId,
  }) async {
    if (IngestFailure.isUnreachableUri(candidate.uri)) {
      // A MediaStore row whose volume has gone resolves to nothing to open.
      return const _Outcome(_OutcomeKind.sourceGone);
    }
    String? createdId;
    try {
      // Tier 2. Only reached by candidates the path key already called new, so
      // this reads 128 KiB for genuinely new photos and nothing for a rescan.
      final contentKey = await ContentKey.compute(
        sizeBytes: candidate.sizeBytes,
        read: (offset, length) => source.readRange(candidate, offset, length),
      );

      final result = await _ledger.insertIfNew(
        source: source.sourceKind,
        sourceRef: candidate.sourceRef,
        contentKey: contentKey,
        eventId: eventId,
        originalFilename: candidate.displayName,
        capturedAtMs: candidate.capturedAtMs,
        originalBytes: candidate.sizeBytes,
      );
      if (!result.isNew) {
        return const _Outcome(_OutcomeKind.duplicate);
      }
      createdId = result.item.id;

      final stored = await _storeDerivative(
        source,
        candidate,
        mediaId: createdId,
        eventId: eventId,
        settings: settings,
      );
      switch (stored) {
        case _StoreResult.stored:
          return _Outcome(_OutcomeKind.imported, mediaId: createdId);
        case _StoreResult.sourceGone:
          return await _rollBack(createdId);
        case _StoreResult.failed:
          // The row exists but has no rendition, so it would be unprintable.
          // Marking it failed keeps it visible for retry instead of looking
          // imported and silently producing nothing at print time.
          await _ledger.setStage(
            createdId,
            MediaStage.failed,
            error: 'Could not store a print-ready copy',
          );
          return const _Outcome(_OutcomeKind.failed);
      }
    } catch (e, st) {
      AppLogger.error(
        'Ingest failed for ${candidate.relativePath}',
        error: e,
        stackTrace: st,
      );
      if (IngestFailure.classify(e) == IngestFailureKind.sourceUnavailable) {
        return await _rollBack(createdId);
      }
      return const _Outcome(_OutcomeKind.failed);
    }
  }

  /// Returns a half-written item to "never seen" so a rescan finds it again.
  Future<_Outcome> _rollBack(String? mediaId) async {
    if (mediaId != null) await _ledger.deleteItem(mediaId);
    return const _Outcome(_OutcomeKind.sourceGone);
  }

  /// Writes the grid thumbnail, if the decode produced one.
  ///
  /// Best effort by design: a missing thumbnail costs a blank tile, and failing
  /// the whole import over one would be losing a photograph to save a preview.
  Future<void> _storeThumb({
    required String mediaId,
    required String? eventId,
    required Uint8List? bytes,
    required int? width,
    required int? height,
  }) async {
    if (bytes == null || bytes.isEmpty) return;
    final path = EventMediaStore.relativePathFor(
      mediaId: mediaId,
      kind: RenditionKind.thumb,
      eventId: eventId,
    );
    try {
      if (await _media.putBytes(path, bytes) == null) return;
      await _ledger.putRendition(MediaRendition(
        mediaId: mediaId,
        kind: RenditionKind.thumb,
        path: path,
        width: width,
        height: height,
        bytes: bytes.length,
        createdAtMs: _nowMs(),
      ));
    } catch (e) {
      AppLogger.debug('Thumbnail store failed for $mediaId: $e');
    }
  }

  Future<_StoreResult> _storeDerivative(
    IngestSource source,
    IngestCandidate candidate, {
    required String mediaId,
    required String? eventId,
    required EventPipelineSettings settings,
  }) async {
    final relativePath = EventMediaStore.relativePathFor(
      mediaId: mediaId,
      kind: RenditionKind.source,
      eventId: eventId,
    );
    try {
      final scaled = await _downscaler.downscale(
        sourceUri: candidate.uri,
        targetShortSide:
            DownscaleTarget.shortSideFor(settings.qualityFactor),
        // Second encode off the same decode. The queue grid has to have
        // something to draw the moment an import finishes, and decoding the
        // print derivative per tile is the memory mistake the old tray made.
        thumbShortSide: RenditionKind.thumbShortSide,
      );
      final file = await _media.putBytes(relativePath, scaled.bytes);
      if (file == null) return _StoreResult.failed;

      await _ledger.putRendition(MediaRendition(
        mediaId: mediaId,
        kind: RenditionKind.source,
        path: relativePath,
        width: scaled.width,
        height: scaled.height,
        bytes: scaled.bytes.length,
        createdAtMs: _nowMs(),
      ));
      await _storeThumb(
        mediaId: mediaId,
        eventId: eventId,
        bytes: scaled.thumbBytes,
        width: scaled.thumbWidth,
        height: scaled.thumbHeight,
      );
      return _StoreResult.stored;
    } catch (e, st) {
      AppLogger.error(
        'Downscale failed for ${candidate.relativePath}',
        error: e,
        stackTrace: st,
      );
      return IngestFailure.classify(e) == IngestFailureKind.sourceUnavailable
          ? _StoreResult.sourceGone
          : _StoreResult.failed;
    }
  }
}

enum _StoreResult { stored, failed, sourceGone }

enum _OutcomeKind { imported, duplicate, failed, sourceGone }

class _Outcome {
  const _Outcome(this.kind, {this.mediaId});

  final _OutcomeKind kind;
  final String? mediaId;
}
