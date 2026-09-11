import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/event_pipeline/event_pipeline_chain.dart';
import '../../models/event_pipeline/event_pipeline_settings.dart';
import '../../models/event_pipeline/media_item.dart';
import '../../models/event_pipeline/media_rendition.dart';
import '../../models/event_pipeline/pipeline_job.dart';
import '../../services/event_pipeline/ai_job_worker.dart';
import '../../services/event_pipeline/event_media_store.dart';
import '../../services/event_pipeline/event_pipeline_runner.dart';
import '../../utils/logger.dart';

/// One stored version of the photograph, ready to draw.
class ItemRendition {
  const ItemRendition({
    required this.kind,
    required this.label,
    this.file,
    this.width,
    this.height,
  });

  final String kind;
  final String label;
  final File? file;
  final int? width;
  final int? height;

  bool get exists => file != null;

  /// `2880×1920`, or null when the dimensions were never recorded.
  String? get dimensions =>
      (width == null || height == null) ? null : '$width×$height';
}

/// What one step of the chain cost, read back from its job record.
class StepTiming {
  const StepTiming({
    required this.step,
    required this.label,
    required this.status,
    this.queuedAtMs,
    this.startedAtMs,
    this.finishedAtMs,
  });

  final String step;
  final String label;
  final String status;

  final int? queuedAtMs;

  /// When the work began. Null while the job is still waiting.
  final int? startedAtMs;

  /// When it finished, for a step that has.
  final int? finishedAtMs;

  DateTime? get finishedAt => finishedAtMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(finishedAtMs!);

  /// How long the step waited in the queue before anything ran.
  ///
  /// Reported separately from [work] because they are different problems: a
  /// long wait means the queue is backed up, a long run means the step itself
  /// is slow, and an operator chasing "why is this taking so long" needs to
  /// know which.
  Duration? get wait {
    if (queuedAtMs == null || startedAtMs == null) return null;
    final ms = startedAtMs! - queuedAtMs!;
    return ms < 0 ? null : Duration(milliseconds: ms);
  }

  /// How long the work itself took.
  Duration? get work {
    if (startedAtMs == null || finishedAtMs == null) return null;
    final ms = finishedAtMs! - startedAtMs!;
    return ms < 0 ? null : Duration(milliseconds: ms);
  }

  bool get hasTiming => queuedAtMs != null;
}

/// Everything about one photograph, and what can still be done to it.
///
/// The screen that did not exist before, and its absence was a real gap: an
/// operator could see *that* something failed but not *why*, which is not
/// enough to act on (spec §8).
class EventItemDetailViewModel extends ChangeNotifier {
  EventItemDetailViewModel({
    required this.mediaId,
    EventPipelineRunner? runner,
    EventMediaStore? mediaStore,
  })  : _runner = runner ?? EventPipelineRunner.instance ?? EventPipelineRunner(),
        _media = mediaStore ?? EventMediaStore();

  final String mediaId;
  final EventPipelineRunner _runner;
  final EventMediaStore _media;

  MediaItem? _item;
  List<ItemRendition> _renditions = const [];
  List<StepTiming> _timings = const [];
  String? _error;
  String? _jobError;
  bool _busy = false;
  bool _removed = false;

  MediaItem? get item => _item;
  bool get isBusy => _busy;
  String? get errorMessage => _error;

  /// True once the item has been removed, so the screen can close itself
  /// rather than sit on a row that no longer exists.
  bool get isRemoved => _removed;

  /// Source, AI and framed side by side — how an operator answers "did the
  /// frame come out right" without going to the printer.
  List<ItemRendition> get renditions => _renditions;

  /// One row per step of the frozen chain: when it was queued, when it ran, and
  /// what it cost. This is how "the AI is slow today" stops being a hunch.
  List<StepTiming> get timings => _timings;

  String get title => _item?.originalFilename ?? mediaId;

  /// The frozen chain, e.g. `AI → Frame → Print`.
  String get chainLabel {
    final steps = _item?.steps ?? const <String>[];
    if (steps.isEmpty) return 'Not queued yet';
    return steps.map(EventPipelineChain.labelFor).join(' → ');
  }

  /// Stage plus the step it stalled on, e.g. `Failed at Print`.
  String get stageLabel {
    final item = _item;
    if (item == null) return '—';
    if (item.stage != MediaStage.failed) return _stageName(item.stage);
    final step = item.currentStep;
    return step == null
        ? 'Failed'
        : 'Failed at ${EventPipelineChain.labelFor(step)}';
  }

  /// **The real error text, not a category.** A category tells an operator
  /// nothing they can act on; "Ribbon end — replace ribbon" tells them exactly
  /// what to do.
  String? get failureReason => _item?.lastError ?? _jobError;

  /// Which card it came off, and where on it.
  String? get sourceLabel {
    final item = _item;
    if (item == null) return null;
    // `{volumeId}:{relPath}:{size}:{mtime}` — only the first two are readable.
    final parts = item.sourceRef.split(':');
    if (parts.length < 2) return item.sourceRef;
    return '${parts[0]} · ${parts[1]}';
  }

  /// When the shutter fired, not when it was imported.
  DateTime? get shotAt => _item?.capturedAtMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(_item!.capturedAtMs!);

  bool get canRetry => _item?.stage == MediaStage.failed;
  bool get canSkipAi =>
      _item != null &&
      !_item!.aiSkipped &&
      _item!.steps.contains(EventPipelineStep.ai) &&
      _item!.stage != MediaStage.done;

  /// Reprint needs something finished to reprint.
  bool get canReprint =>
      _renditions.any((r) => r.exists && r.kind != RenditionKind.thumb);

  Future<void> start() async {
    await _runner.ensureStarted();
    await refresh();
  }

  Future<void> refresh() async {
    final ledger = _runner.ledger;
    if (ledger == null) {
      _error = 'Storage is unavailable.';
      notifyListeners();
      return;
    }
    try {
      final item = await ledger.findById(mediaId);
      _item = item;
      if (item == null) {
        _removed = true;
        notifyListeners();
        return;
      }
      _renditions = await _loadRenditions();
      _timings = await _loadTimings(item);
      _jobError = await _readJobError(item);
      _error = null;
    } catch (e, st) {
      AppLogger.error('Item detail failed', error: e, stackTrace: st);
      _error = 'Could not read this photo.';
    }
    notifyListeners();
  }

  Future<List<ItemRendition>> _loadRenditions() async {
    final ledger = _runner.ledger;
    if (ledger == null) return const [];
    final stored = <String, MediaRendition>{
      for (final r in await ledger.renditionsFor(mediaId)) r.kind: r,
    };
    // Thumbnails are a grid optimisation, not a version of the photograph, so
    // they are deliberately not one of the three shown here.
    const shown = <String, String>{
      RenditionKind.source: 'Source',
      RenditionKind.ai: 'AI',
      RenditionKind.framed: 'Framed',
    };
    final out = <ItemRendition>[];
    for (final entry in shown.entries) {
      final r = stored[entry.key];
      out.add(ItemRendition(
        kind: entry.key,
        label: entry.value,
        file: r == null ? null : await _media.getFile(r.path),
        width: r?.width,
        height: r?.height,
      ));
    }
    return out;
  }

  /// Reads each step's job row for its timings.
  ///
  /// Derived rather than stored on the item: the job already records when it
  /// was enqueued, claimed and last transitioned, so a second copy on the item
  /// would only be another thing to keep in step.
  Future<List<StepTiming>> _loadTimings(MediaItem item) async {
    final queue = _runner.queue;
    if (queue == null || item.steps.isEmpty) return const [];
    final out = <StepTiming>[];
    for (final step in item.steps) {
      final job = await queue.findFor(kind: step, mediaId: item.id);
      if (job == null) continue;
      final finished = job.status == PipelineJobStatus.done ||
          job.status == PipelineJobStatus.failed;
      out.add(StepTiming(
        step: step,
        label: EventPipelineChain.labelFor(step),
        status: job.status,
        queuedAtMs: job.createdAtMs,
        startedAtMs: job.startedAtMs,
        // updated_at_ms is the last transition, which for a finished job is
        // the moment it finished. For one still running it is the claim, so
        // reporting it as a finish time would invent a duration.
        finishedAtMs: finished ? job.updatedAtMs : null,
      ));
    }
    return out;
  }

  Future<String?> _readJobError(MediaItem item) async {
    final queue = _runner.queue;
    final step = item.currentStep;
    if (queue == null || step == null) return null;
    final job = await queue.findFor(kind: step, mediaId: item.id);
    return job?.lastError;
  }

  Future<void> retry() async {
    final ledger = _runner.ledger;
    final queue = _runner.queue;
    final item = _item;
    if (ledger == null || queue == null || item == null || _busy) return;
    await _act(() async {
      final step = item.currentStep;
      if (step == null) return;
      await queue.retryFor(kind: step, mediaId: item.id);
      await ledger.setStage(item.id, MediaStage.forStep(step));
    });
  }

  Future<void> skipAi() async {
    final ledger = _runner.ledger;
    final queue = _runner.queue;
    if (ledger == null || queue == null || _busy) return;
    await _act(() async {
      await SkipAiAction(ledger: ledger, queue: queue).apply([mediaId]);
    });
  }

  /// Another copy of the finished output — framed, else AI, else the import.
  Future<void> reprint() async {
    if (_busy) return;
    await _act(() => _runner.reprint(mediaId));
  }

  Future<void> remove() async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      await _runner.removeItem(mediaId);
      _removed = true;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _act(Future<void> Function() body) async {
    _busy = true;
    notifyListeners();
    try {
      await body();
      await refresh();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  static String _stageName(String stage) {
    switch (stage) {
      case MediaStage.ingested:
        return 'Imported';
      case MediaStage.queued:
        return 'Queued';
      case MediaStage.ai:
        return 'Waiting on AI';
      case MediaStage.framing:
        return 'Framing';
      case MediaStage.printing:
        return 'Printing';
      case MediaStage.done:
        return 'Done';
      case MediaStage.paused:
        return 'Paused';
      default:
        return stage;
    }
  }
}
