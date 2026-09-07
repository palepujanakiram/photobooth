import 'dart:convert';

import 'event_pipeline_settings.dart';

/// Where an image entered the pipeline. Persisted in `evp_media_items.source`
/// and half of the `(source, source_ref)` dedupe key, so these values are stable.
abstract final class MediaSource {
  static const String sdCard = 'sdcard';
  static const String folder = 'folder';
  static const String gallery = 'gallery';
  static const String camera = 'camera';
  static const String ptp = 'ptp';
  static const String sidecar = 'sidecar';
  static const String uvc = 'uvc';
}

/// Coarse position of an item, denormalised so the console can group without
/// recomputing from `steps` and `stepIndex`.
abstract final class MediaStage {
  /// Imported and stored, awaiting operator selection.
  static const String ingested = 'INGESTED';

  /// Selected; steps frozen; waiting for the first worker to pick it up.
  static const String queued = 'QUEUED';

  static const String ai = 'AI';
  static const String framing = 'FRAMING';
  static const String printing = 'PRINTING';
  static const String done = 'DONE';
  static const String failed = 'FAILED';
  static const String paused = 'PAUSED';

  /// Stage implied by the step an item is currently sitting on.
  ///
  /// A null [step] means the chain is exhausted, which is [done] — including the
  /// case of an empty chain, where selection stores the item without processing.
  static String forStep(String? step) {
    switch (step) {
      case EventPipelineStep.ai:
        return ai;
      case EventPipelineStep.frame:
        return framing;
      case EventPipelineStep.print:
        return printing;
      default:
        return done;
    }
  }
}

/// One image in the pipeline ledger.
///
/// The row is the durable record of a photograph; MediaStore forgets a card the
/// moment it is unmounted, so every "already imported" answer comes from here.
class MediaItem {
  const MediaItem({
    required this.id,
    required this.source,
    required this.sourceRef,
    required this.contentKey,
    required this.stage,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.eventId,
    this.originalFilename,
    this.capturedAtMs,
    this.originalBytes,
    this.remoteSessionId,
    this.remotePhotoId,
    this.steps = const <String>[],
    this.stepIndex = 0,
    this.selectedAtMs,
    this.aiSkipped = false,
    this.lastError,
  });

  final String id;
  final String? eventId;

  /// One of [MediaSource].
  final String source;

  /// Tier-1 dedupe key: `{volumeId}:{relPath}:{size}:{mtimeMs}` for a card.
  ///
  /// Size and mtime are part of it deliberately. Path alone silently skips new
  /// photos after a card is reformatted and the camera's numbering resets to
  /// `IMG_0001` — a false negative, which is the dangerous direction.
  final String sourceRef;

  /// Tier-2 dedupe key: `sha1(size ‖ first 64KiB ‖ last 64KiB)` of the original.
  /// Catches the same photo arriving by two routes (tethered, then on the card).
  final String contentKey;

  final String? originalFilename;

  /// EXIF capture time. From MediaStore's `datetaken` on the card path, so no
  /// file read is needed to populate it.
  final int? capturedAtMs;

  /// Size of the file on the card, not of the derivative we keep.
  final int? originalBytes;

  final String stage;

  /// Filled by the mirror's `session` step. The AI step blocks until it is set.
  final String? remoteSessionId;
  final String? remotePhotoId;

  /// The chain frozen onto this item at selection or capture-confirm time.
  ///
  /// Frozen rather than read live so a settings change mid-event cannot alter
  /// work already in flight. See the workflow spec §2.2.
  final List<String> steps;

  final int stepIndex;
  final int? selectedAtMs;

  /// True once an operator used **Skip AI** on this item, so a result that never
  /// went through AI is distinguishable from one that did.
  final bool aiSkipped;

  final String? lastError;
  final int createdAtMs;
  final int updatedAtMs;

  /// Step this item is waiting on, or null when the chain is exhausted.
  String? get currentStep =>
      stepIndex >= 0 && stepIndex < steps.length ? steps[stepIndex] : null;

  bool get isSelected => selectedAtMs != null;
  bool get isChainComplete => stepIndex >= steps.length;

  MediaItem copyWith({
    String? eventId,
    String? stage,
    String? remoteSessionId,
    String? remotePhotoId,
    List<String>? steps,
    int? stepIndex,
    int? selectedAtMs,
    bool? aiSkipped,
    String? lastError,
    int? updatedAtMs,
  }) {
    return MediaItem(
      id: id,
      eventId: eventId ?? this.eventId,
      source: source,
      sourceRef: sourceRef,
      contentKey: contentKey,
      originalFilename: originalFilename,
      capturedAtMs: capturedAtMs,
      originalBytes: originalBytes,
      stage: stage ?? this.stage,
      remoteSessionId: remoteSessionId ?? this.remoteSessionId,
      remotePhotoId: remotePhotoId ?? this.remotePhotoId,
      steps: steps ?? this.steps,
      stepIndex: stepIndex ?? this.stepIndex,
      selectedAtMs: selectedAtMs ?? this.selectedAtMs,
      aiSkipped: aiSkipped ?? this.aiSkipped,
      lastError: lastError ?? this.lastError,
      createdAtMs: createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'event_id': eventId,
        'source': source,
        'source_ref': sourceRef,
        'content_key': contentKey,
        'original_filename': originalFilename,
        'captured_at_ms': capturedAtMs,
        'original_bytes': originalBytes,
        'stage': stage,
        'remote_session_id': remoteSessionId,
        'remote_photo_id': remotePhotoId,
        'steps_json': jsonEncode(steps),
        'step_index': stepIndex,
        'selected_at_ms': selectedAtMs,
        'ai_skipped': aiSkipped ? 1 : 0,
        'last_error': lastError,
        'created_at_ms': createdAtMs,
        'updated_at_ms': updatedAtMs,
      };

  factory MediaItem.fromRow(Map<String, Object?> row) {
    return MediaItem(
      id: (row['id'] ?? '').toString(),
      eventId: row['event_id'] as String?,
      source: (row['source'] ?? '').toString(),
      sourceRef: (row['source_ref'] ?? '').toString(),
      contentKey: (row['content_key'] ?? '').toString(),
      originalFilename: row['original_filename'] as String?,
      capturedAtMs: row['captured_at_ms'] as int?,
      originalBytes: row['original_bytes'] as int?,
      stage: (row['stage'] ?? MediaStage.ingested).toString(),
      remoteSessionId: row['remote_session_id'] as String?,
      remotePhotoId: row['remote_photo_id'] as String?,
      steps: decodeSteps(row['steps_json'] as String?),
      stepIndex: (row['step_index'] as int?) ?? 0,
      selectedAtMs: row['selected_at_ms'] as int?,
      aiSkipped: (row['ai_skipped'] as int? ?? 0) != 0,
      lastError: row['last_error'] as String?,
      createdAtMs: (row['created_at_ms'] as int?) ?? 0,
      updatedAtMs: (row['updated_at_ms'] as int?) ?? 0,
    );
  }

  /// Reads a frozen chain back, dropping anything this build no longer knows.
  ///
  /// A step kind removed in a later release would otherwise strand items from an
  /// older build forever, since no worker would ever claim it.
  static List<String> decodeSteps(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <String>[];
      return EventPipelineStep.normalize(decoded.map((e) => e.toString()));
    } catch (_) {
      return const <String>[];
    }
  }
}
