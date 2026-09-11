import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/event_pipeline/media_item.dart';
import '../../models/event_pipeline/media_rendition.dart';
import '../../models/event_pipeline/pipeline_job.dart';
import '../../services/event_manager.dart';
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
    this.printPosition,
    this.isOnPrinter = false,
  });

  final MediaItem item;

  /// 1-based place in the print queue, or null when it is not waiting to print.
  ///
  /// Shown on the tile so an operator watching for a particular photo can see
  /// how far down it is instead of guessing.
  final int? printPosition;

  /// True for the one job actually on the printer.
  final bool isOnPrinter;

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
        // Forty photos all reading "Printing" is untrue: exactly one is on the
        // printer and the rest are queued behind it.
        if (isOnPrinter) return 'Printing';
        return printPosition == null
            ? 'In print queue'
            : 'In print queue · $printPosition';
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
    EventManager? events,
    String? initialFilter,
    int pageSize = defaultPageSize,
    Duration refreshInterval = const Duration(seconds: 4),
  })  : _runner = runner ?? EventPipelineRunner.instance ?? EventPipelineRunner(),
        _media = mediaStore ?? EventMediaStore(),
        _events = events ?? EventManager(),
        _pageSize = pageSize,
        _refreshInterval = refreshInterval,
        _filter = QueueFilter.normalize(initialFilter);

  /// Roughly one screenful and a half. Pagination bounds how many entries are
  /// live; the thumbnail rendition bounds what each one costs. Both, not
  /// either — a 3,000-photo event would otherwise build 3,000 tiles.
  static const int defaultPageSize = 60;

  final EventPipelineRunner _runner;
  final EventMediaStore _media;
  final EventManager _events;
  final int _pageSize;
  final Duration _refreshInterval;

  Timer? _timer;
  bool _busy = false;
  String? _error;
  List<QueueEntry> _entries = const [];
  EventPipelineStats _stats = const EventPipelineStats();
  String _filter;
  String? _sourceFilter;
  Map<String, int> _sourceCounts = const <String, int>{};
  String? _eventId;
  int _loaded = 0;
  int _totalInFilter = 0;
  bool _selectionMode = false;
  final Set<String> _selectedIds = <String>{};

  /// Everything the pipeline holds, unfiltered.
  List<QueueEntry> get entries => _entries;

  String get filter => _filter;

  /// What the grid shows. The filter is applied by the query, not in memory —
  /// a filter that pages over rows it then throws away is a filter that runs
  /// out of pages.
  List<QueueEntry> get visibleEntries => _entries;

  /// Whether there is another page behind the one on screen.
  bool get hasMore => _loaded < _totalInFilter;

  /// Total matching the current filter, which is more than is loaded.
  int get totalInFilter => _totalInFilter;

  /// The source being shown, or null for all of them.
  String? get sourceFilter => _sourceFilter;

  /// Sources that actually contributed photos, with their counts.
  ///
  /// Only shown when there is more than one: an event that only ever imported
  /// from a card has nothing to choose between, and a single dead chip is
  /// clutter on a screen that needs to stay readable.
  List<QueueFilterOption> get sourceOptions {
    final present = <QueueFilterOption>[
      for (final source in MediaSource.filterOrder)
        if ((_sourceCounts[source] ?? 0) > 0)
          QueueFilterOption(
            value: source,
            label: MediaSource.labelFor(source),
            count: _sourceCounts[source]!,
          ),
    ];
    if (present.length < 2) return const [];
    return <QueueFilterOption>[
      QueueFilterOption(
        value: QueueFilter.allSources,
        label: 'All sources',
        count: present.fold<int>(0, (sum, o) => sum + o.count),
      ),
      ...present,
    ];
  }

  /// Narrows the grid to one source, or back to all of them.
  Future<void> setSourceFilter(String? source) async {
    final next = source == QueueFilter.allSources ? null : source;
    if (_sourceFilter == next) return;
    _sourceFilter = next;
    _selectedIds.clear();
    _loaded = 0;
    await refresh();
  }

  /// Filters that actually have photos behind them, with their counts.
  ///
  /// Counted from the ledger rather than the loaded page: with pagination the
  /// page is a window, and chips derived from it would shrink as the operator
  /// scrolled.
  List<QueueFilterOption> get filterOptions {
    final counts = <String, int>{
      MediaStage.ingested: _stats.imported,
      MediaStage.queued: _stats.queued,
      MediaStage.ai: _stats.ai,
      MediaStage.framing: _stats.framing,
      MediaStage.printing: _stats.printing,
      MediaStage.done: _stats.done,
      MediaStage.failed: _stats.failed,
    };
    return <QueueFilterOption>[
      QueueFilterOption(
        value: QueueFilter.all,
        label: 'All',
        count: _stats.total,
      ),
      // Empty stages are omitted so an AI-off event carries no dead "AI 0" chip.
      for (final stage in QueueFilter.stageOrder)
        if ((counts[stage] ?? 0) > 0)
          QueueFilterOption(
            value: stage,
            label: QueueFilter.labelFor(stage),
            count: counts[stage]!,
          ),
    ];
  }

  /// Changes the filter and reloads from the first page.
  ///
  /// Selection is cleared: `All` inside a filter means "everything matching
  /// this filter", so carrying ticks across a filter change would let an action
  /// reach items the operator can no longer see.
  Future<void> setFilter(String value) async {
    if (_filter == value) return;
    _filter = value;
    _selectedIds.clear();
    // Back to a single page. refresh() deliberately re-reads however much is
    // already on screen so a poll does not scroll the operator back to the top,
    // and carrying that count into a new filter would load one page's worth of
    // the wrong size.
    _loaded = 0;
    await refresh();
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
    _eventId = await _events.getEventId();
    await refresh();
    _timer = Timer.periodic(_refreshInterval, (_) => unawaited(refresh()));
  }

  /// Re-reads the pages already on screen, so a poll does not scroll the
  /// operator back to the top of a list they had paged through.
  Future<void> refresh() async {
    await _load(limit: _loaded == 0 ? _pageSize : _loaded, offset: 0);
  }

  /// Appends the next page. The "Load more" action, and the scroll trigger.
  Future<void> loadMore() async {
    if (!hasMore || _busy) return;
    await _load(limit: _pageSize, offset: _loaded, append: true);
  }

  Future<void> _load({
    required int limit,
    required int offset,
    bool append = false,
  }) async {
    final ledger = _runner.ledger;
    if (ledger == null) {
      _entries = const [];
      notifyListeners();
      return;
    }
    try {
      final stage = _filter == QueueFilter.all ? null : _filter;
      final stages =
          _filter == QueueFilter.working ? QueueFilter.workingStages : null;
      final items = await ledger.listPage(
        limit: limit,
        offset: offset,
        eventId: _eventId,
        stage: stages == null ? stage : null,
        stages: stages,
        source: _sourceFilter,
      );
      final page = await _decorate(ledger, items);
      _entries = append ? <QueueEntry>[..._entries, ...page] : page;
      _loaded = _entries.length;
      _totalInFilter = await ledger.countItems(
        eventId: _eventId,
        stage: stages == null ? stage : null,
        stages: stages,
        source: _sourceFilter,
      );
      _sourceCounts = await ledger.sourceCounts(eventId: _eventId);
      _stats = await _readStats(ledger);
      _error = null;
    } catch (e, st) {
      AppLogger.error('Queue refresh failed', error: e, stackTrace: st);
      _error = 'Could not read the queue.';
    }
    notifyListeners();
  }

  Future<EventPipelineStats> _readStats(EventPipelineLedger ledger) async {
    final queue = _runner.queue;
    return EventPipelineStats.fromStageCounts(
      await ledger.stageCounts(eventId: _eventId),
      printPaused:
          await queue?.isKindPaused(EventPipelineStepNames.print) ?? false,
      queuePaused: await queue?.isPaused() ?? false,
    );
  }

  Future<List<QueueEntry>> _decorate(
    EventPipelineLedger ledger,
    List<MediaItem> items,
  ) async {
    // One query for the whole print queue rather than one per tile: the order
    // is a property of the queue, not of any single item.
    final printOrder = await _printQueueOrder();
    final out = <QueueEntry>[];
    for (final item in items) {
      final place = printOrder[item.id];
      out.add(QueueEntry(
        item: item,
        thumbnailFile: await _thumbFor(ledger, item),
        jobError: await _errorFor(item),
        printPosition: place?.position,
        isOnPrinter: place?.onPrinter ?? false,
      ));
    }
    return out;
  }

  Future<Map<String, _PrintPlace>> _printQueueOrder() async {
    final queue = _runner.queue;
    if (queue == null) return const <String, _PrintPlace>{};
    final jobs = await queue.openJobsInOrder(EventPipelineStepNames.print);
    final out = <String, _PrintPlace>{};
    var waiting = 0;
    for (final job in jobs) {
      final onPrinter = job.status == PipelineJobStatus.claimed;
      // The one on the printer has no place in the queue; it has left it.
      out[job.mediaId] = _PrintPlace(
        position: onPrinter ? null : ++waiting,
        onPrinter: onPrinter,
      );
    }
    return out;
  }

  /// The grid tile's picture: the dedicated thumbnail, never a print derivative.
  ///
  /// Falling back to the print copy would put a 2880 px JPEG behind every tile,
  /// which is exactly the decode cost the thumbnail exists to avoid. An item
  /// with no thumbnail yet gets a blank tile instead — cheap and honest.
  Future<File?> _thumbFor(EventPipelineLedger ledger, MediaItem item) async {
    final renditions = await ledger.renditionsFor(item.id);
    for (final r in renditions) {
      if (r.kind == RenditionKind.thumb) return _media.getFile(r.path);
    }
    return null;
  }

  Future<String?> _errorFor(MediaItem item) async {
    if (item.lastError != null) return item.lastError;
    final queue = _runner.queue;
    final step = item.currentStep;
    if (queue == null || step == null) return null;
    final job = await queue.findFor(kind: step, mediaId: item.id);
    return job?.lastError;
  }

  // ------------------------------------------------------------- selection

  /// Whether the operator is ticking items rather than browsing.
  bool get selectionMode => _selectionMode;

  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  int get selectedCount => _selectedIds.length;
  bool get hasSelection => _selectedIds.isNotEmpty;
  bool isSelected(QueueEntry entry) => _selectedIds.contains(entry.item.id);

  /// The selected entries that are actually on screen.
  List<QueueEntry> get selectedEntries =>
      [for (final e in _entries) if (_selectedIds.contains(e.item.id)) e];

  void enterSelection() {
    if (_selectionMode) return;
    _selectionMode = true;
    notifyListeners();
  }

  void exitSelection() {
    _selectionMode = false;
    _selectedIds.clear();
    notifyListeners();
  }

  void toggleSelected(QueueEntry entry) {
    if (!_selectedIds.remove(entry.item.id)) _selectedIds.add(entry.item.id);
    notifyListeners();
  }

  /// Ticks everything currently loaded under this filter.
  ///
  /// Bounded to what is loaded on purpose: an action must never reach items the
  /// operator has not seen. Filter to `Failed`, tap `All`, `Retry` is still
  /// three taps for the bulk case without making it the default.
  void selectAllLoaded() {
    _selectionMode = true;
    _selectedIds
      ..clear()
      ..addAll(_entries.map((e) => e.item.id));
    notifyListeners();
  }

  void selectNone() {
    _selectedIds.clear();
    notifyListeners();
  }

  /// Whether an action makes sense for what is ticked.
  ///
  /// Actions appear only when valid, so an operator is never offered a control
  /// that will silently do nothing. A bare "Retry all" is the button that
  /// quietly reprints eighty photos when someone meant three, and on dye-sub
  /// media that is real consumable spent for nothing.
  bool get canRetrySelected => selectedEntries.any((e) => e.isFailed);
  bool get canSkipAiSelected =>
      selectedEntries.any((e) => e.item.stage == MediaStage.ai);
  bool get canReprintSelected => selectedEntries.any((e) => e.isDone);
  bool get canRemoveSelected => hasSelection;

  /// Requeues the ticked failures, and nothing else.
  Future<int> retrySelected() async {
    final ledger = _runner.ledger;
    final queue = _runner.queue;
    if (ledger == null || queue == null || _busy) return 0;
    return _act(() async {
      var changed = 0;
      for (final entry in selectedEntries.where((e) => e.isFailed)) {
        final step = entry.item.currentStep;
        if (step == null) continue;
        await queue.retryFor(kind: step, mediaId: entry.item.id);
        await ledger.setStage(entry.item.id, MediaStage.forStep(step));
        changed++;
      }
      return changed;
    });
  }

  /// Drops AI from the ticked items so the rest of their chain can finish.
  Future<int> skipAiSelected() async {
    final ledger = _runner.ledger;
    final queue = _runner.queue;
    if (ledger == null || queue == null || _busy) return 0;
    return _act(() async {
      final ids = [
        for (final e in selectedEntries)
          if (e.item.stage == MediaStage.ai) e.item.id,
      ];
      return SkipAiAction(ledger: ledger, queue: queue).apply(ids);
    });
  }

  /// Queues another print of each ticked item's finished output.
  ///
  /// Does **not** re-run a stage: the operator wants another print of what they
  /// can see, not a fresh generation that might come out different.
  Future<int> reprintSelected() async {
    if (_busy) return 0;
    return _act(() async {
      var queued = 0;
      for (final entry in selectedEntries.where((e) => e.isDone)) {
        if (await _runner.reprint(entry.item.id)) queued++;
      }
      return queued;
    });
  }

  /// Removes the ticked items from this event.
  Future<int> removeSelected() async {
    if (_busy) return 0;
    return _act(() async {
      var removed = 0;
      for (final entry in selectedEntries) {
        if (await _runner.removeItem(entry.item.id)) removed++;
      }
      return removed;
    });
  }

  Future<int> _act(Future<int> Function() body) async {
    _busy = true;
    notifyListeners();
    try {
      final n = await body();
      _selectedIds.clear();
      _selectionMode = false;
      await refresh();
      return n;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ----------------------------------------------------------- pause/resume

  /// True when the operator has held every stage.
  bool get isPaused => _stats.queuePaused;

  /// Whether work is actually moving, for the live indicator.
  ///
  /// The diagnostic question "is this thing stuck?" is answered by this rather
  /// than by a Run now button: if it says processing and the counts do not
  /// move, that is a real fault worth surfacing.
  bool get isProcessing => !isPaused && _stats.inFlight > 0;

  /// Holds or releases the queue. Survives a restart — it is queue state.
  Future<void> setPaused(bool paused) async {
    final queue = _runner.queue;
    if (queue == null || _busy) return;
    _busy = true;
    notifyListeners();
    try {
      await queue.setPaused(paused);
      await refresh();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // --------------------------------------------------------------- actions

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

  /// The "no source filter" sentinel, distinct from any [MediaSource].
  static const String allSources = 'ALL_SOURCES';

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

/// Where one item sits in the print queue.
class _PrintPlace {
  const _PrintPlace({required this.position, required this.onPrinter});

  final int? position;
  final bool onPrinter;
}
