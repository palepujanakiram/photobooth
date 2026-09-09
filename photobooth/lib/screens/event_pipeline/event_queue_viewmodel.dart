import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/event_pipeline/media_item.dart';
import '../../services/event_pipeline/ai_job_worker.dart';
import '../../services/event_pipeline/event_media_store.dart';
import '../../services/event_pipeline/event_pipeline_ledger.dart';
import '../../services/event_pipeline/event_pipeline_runner.dart';
import '../../services/event_pipeline/event_pipeline_stats.dart';
import '../../utils/logger.dart';

/// One row in the queue view: the item, where its picture is, and why it stalled.
class QueueEntry {
  const QueueEntry({
    required this.item,
    this.thumbnailFile,
    this.jobError,
  });

  final MediaItem item;

  /// Best rendition on disk — framed, else AI, else the imported derivative.
  final File? thumbnailFile;

  /// Last error from the job this item is sitting on, when there is one.
  final String? jobError;

  String get stageLabel {
    switch (item.stage) {
      case MediaStage.ingested:
        return 'Imported';
      case MediaStage.queued:
        return 'Queued';
      case MediaStage.ai:
        return 'AI';
      case MediaStage.framing:
        return 'Framing';
      case MediaStage.printing:
        return 'Printing';
      case MediaStage.done:
        return item.aiSkipped ? 'Done · AI skipped' : 'Done';
      case MediaStage.failed:
        return 'Failed';
      case MediaStage.paused:
        return 'Paused';
      default:
        return item.stage;
    }
  }

  bool get isFailed => item.stage == MediaStage.failed;
  bool get isDone => item.stage == MediaStage.done;
}

/// Lists what the pipeline is holding, so imported photos are visible.
///
/// Without this the only feedback after an import is a counter — the photos
/// themselves are in the ledger and on disk but nothing shows them, which makes
/// a stalled queue indistinguishable from a lost one.
class EventQueueViewModel extends ChangeNotifier {
  EventQueueViewModel({
    EventPipelineRunner? runner,
    EventMediaStore? mediaStore,
    String? initialFilter,
    Duration refreshInterval = const Duration(seconds: 4),
  })  : _runner = runner ?? EventPipelineRunner.instance ?? EventPipelineRunner(),
        _media = mediaStore ?? EventMediaStore(),
        _refreshInterval = refreshInterval,
        _filter = QueueFilter.normalize(initialFilter);

  final EventPipelineRunner _runner;
  final EventMediaStore _media;
  final Duration _refreshInterval;

  Timer? _timer;
  bool _busy = false;
  String? _error;
  List<QueueEntry> _entries = const [];
  EventPipelineStats _stats = const EventPipelineStats();
  String _filter;

  /// Everything the pipeline holds, unfiltered.
  List<QueueEntry> get entries => _entries;

  String get filter => _filter;

  /// What the grid shows under the current filter.
  List<QueueEntry> get visibleEntries {
    if (_filter == QueueFilter.all) return _entries;
    if (_filter == QueueFilter.working) {
      return [
        for (final e in _entries)
          if (QueueFilter.workingStages.contains(e.item.stage)) e,
      ];
    }
    return [for (final e in _entries) if (e.item.stage == _filter) e];
  }

  /// Filters that actually have photos behind them, with their counts.
  ///
  /// Empty stages are omitted so an AI-off event carries no dead "AI 0" chip.
  List<QueueFilterOption> get filterOptions {
    final counts = <String, int>{};
    for (final e in _entries) {
      counts[e.item.stage] = (counts[e.item.stage] ?? 0) + 1;
    }
    return <QueueFilterOption>[
      QueueFilterOption(
        value: QueueFilter.all,
        label: 'All',
        count: _entries.length,
      ),
      for (final stage in QueueFilter.stageOrder)
        if ((counts[stage] ?? 0) > 0)
          QueueFilterOption(
            value: stage,
            label: QueueFilter.labelFor(stage),
            count: counts[stage]!,
          ),
    ];
  }

  void setFilter(String value) {
    if (_filter == value) return;
    _filter = value;
    notifyListeners();
  }
  EventPipelineStats get stats => _stats;
  bool get isBusy => _busy;
  String? get errorMessage => _error;
  bool get isEmpty => _entries.isEmpty;

  /// True when the filter hides everything but photos do exist.
  bool get isFilteredEmpty => _entries.isNotEmpty && visibleEntries.isEmpty;

  int get failedCount => _entries.where((e) => e.isFailed).length;
  bool get hasFailed => failedCount > 0;

  /// Items stuck waiting on AI — what **Skip AI** acts on.
  List<QueueEntry> get stuckOnAi =>
      [for (final e in _entries) if (e.item.stage == MediaStage.ai) e];

  Future<void> start() async {
    await _runner.ensureStarted();
    await refresh();
    _timer = Timer.periodic(_refreshInterval, (_) => unawaited(refresh()));
  }

  Future<void> refresh() async {
    final ledger = _runner.ledger;
    if (ledger == null) {
      _entries = const [];
      notifyListeners();
      return;
    }
    try {
      final items = await _loadItems(ledger);
      _entries = items;
      _stats = EventPipelineStats.fromStageCounts(
        await ledger.stageCounts(),
        printPaused: await _isPrintPaused(),
      );
      _error = null;
    } catch (e, st) {
      AppLogger.error('Queue refresh failed', error: e, stackTrace: st);
      _error = 'Could not read the queue.';
    }
    notifyListeners();
  }

  Future<bool> _isPrintPaused() async {
    final queue = _runner.queue;
    if (queue == null) return false;
    return queue.isKindPaused(EventPipelineStepNames.print);
  }

  Future<List<QueueEntry>> _loadItems(EventPipelineLedger ledger) async {
    // Newest first: during an event the operator cares about what just came in.
    final rows = <MediaItem>[];
    for (final stage in const [
      MediaStage.failed,
      MediaStage.printing,
      MediaStage.framing,
      MediaStage.ai,
      MediaStage.queued,
      MediaStage.ingested,
      MediaStage.done,
    ]) {
      rows.addAll(await ledger.listByStage(stage, limit: 60));
    }

    final out = <QueueEntry>[];
    for (final item in rows) {
      final rendition = await ledger.bestRenditionForPrint(item.id);
      out.add(QueueEntry(
        item: item,
        thumbnailFile: rendition == null
            ? null
            : await _media.getFile(rendition.path),
        jobError: await _errorFor(item),
      ));
    }
    return out;
  }

  Future<String?> _errorFor(MediaItem item) async {
    if (item.lastError != null) return item.lastError;
    final queue = _runner.queue;
    final step = item.currentStep;
    if (queue == null || step == null) return null;
    final job = await queue.findFor(kind: step, mediaId: item.id);
    return job?.lastError;
  }

  /// Requeues everything that failed, for the whole pipeline.
  Future<void> retryFailed() async {
    final queue = _runner.queue;
    if (queue == null || _busy) return;
    _busy = true;
    notifyListeners();
    try {
      for (final kind in EventPipelineStepNames.all) {
        await queue.retryFailed(kind);
      }
      // Items were parked at FAILED; put them back on their current step.
      final ledger = _runner.ledger;
      if (ledger != null) {
        for (final entry in _entries.where((e) => e.isFailed)) {
          final step = entry.item.currentStep;
          if (step == null) continue;
          await ledger.setStage(entry.item.id, MediaStage.forStep(step));
        }
      }
      await refresh();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Drops AI from every stuck item so the rest of the chain can finish.
  ///
  /// The operator's way out of an event whose link never came back.
  Future<int> skipAiForStuck() async {
    final ledger = _runner.ledger;
    final queue = _runner.queue;
    if (ledger == null || queue == null || _busy) return 0;
    _busy = true;
    notifyListeners();
    try {
      final ids = stuckOnAi.map((e) => e.item.id).toList();
      final changed =
          await SkipAiAction(ledger: ledger, queue: queue).apply(ids);
      await refresh();
      return changed;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// One selectable status filter with its live count.
class QueueFilterOption {
  const QueueFilterOption({
    required this.value,
    required this.label,
    required this.count,
  });

  final String value;
  final String label;
  final int count;
}

/// Status filters, in pipeline order.
abstract final class QueueFilter {
  static const String all = 'ALL';

  /// Everything in flight, as the hub's single "WORKING" counter shows it.
  ///
  /// Not a stage — a photo is at exactly one of AI, framing or printing — but
  /// the hub deliberately collapses the three into one number, so tapping it
  /// has to land on the same set rather than an arbitrary one of them.
  static const String working = 'WORKING';

  static const List<String> workingStages = <String>[
    MediaStage.ai,
    MediaStage.framing,
    MediaStage.printing,
  ];

  /// Accepts a stage from the hub's counters, falling back to [all].
  ///
  /// The hub passes a route argument, which is untyped by the time it arrives;
  /// an unknown value must land on a full queue rather than an empty grid.
  static String normalize(String? value) {
    final trimmed = value?.trim().toUpperCase() ?? '';
    if (trimmed.isEmpty || trimmed == all) return all;
    if (trimmed == working) return working;
    return stageOrder.contains(trimmed) ? trimmed : all;
  }

  /// Stage order matches the chain, so the chips read left to right the way a
  /// photo actually travels — with the two terminal states last.
  static const List<String> stageOrder = <String>[
    MediaStage.ingested,
    MediaStage.queued,
    MediaStage.ai,
    MediaStage.framing,
    MediaStage.printing,
    MediaStage.done,
    MediaStage.failed,
  ];

  static String labelFor(String stage) {
    switch (stage) {
      case MediaStage.ingested:
        return 'Imported';
      case MediaStage.queued:
        return 'Queued';
      case MediaStage.ai:
        return 'AI';
      case MediaStage.framing:
        return 'Framing';
      case MediaStage.printing:
        return 'Printing';
      case MediaStage.done:
        return 'Done';
      case MediaStage.failed:
        return 'Failed';
      default:
        return stage;
    }
  }
}

/// Job kind names, kept here so the view model does not import the settings
/// model purely for three string constants.
abstract final class EventPipelineStepNames {
  static const String ai = 'ai';
  static const String frame = 'frame';
  static const String print = 'print';
  static const List<String> all = <String>[ai, frame, print];
}
