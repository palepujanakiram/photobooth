import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

import '../../models/event_pipeline/event_frame.dart';
import '../../models/event_pipeline/event_pipeline_settings.dart';
import '../../models/event_pipeline/media_item.dart';
import '../../utils/logger.dart';
import '../event_manager.dart';
import 'ai_job_worker.dart';
import 'event_frame_cache.dart';
import 'event_media_store.dart';
import 'event_mirror_worker.dart';
import 'event_pipeline_config.dart';
import 'event_pipeline_db.dart';
import 'event_pipeline_ledger.dart';
import 'event_pipeline_queue.dart';
import 'event_pipeline_service_channel.dart';
import 'frame_compositor.dart';
import 'frame_job_worker.dart';
import 'print_job_worker.dart';

/// Owns and runs the event pipeline's workers.
///
/// Everything before this was a set of parts nothing started. This is the single
/// place that opens the database, wires the four workers to one queue, and keeps
/// them running — so a station screen only has to say "start".
///
/// **Idempotent and safe to call repeatedly.** Stations come and go as the
/// operator switches roles; the workers should not.
class EventPipelineRunner {
  EventPipelineRunner({
    EventPipelineConfig? config,
    EventManager? eventManager,
    EventMediaStore? mediaStore,
    FrameCompositor? compositor,
    Future<EventPipelineDb?> Function()? openDb,
    EventPrintFn? printFn,
    EventPipelineServiceChannel? serviceChannel,
  })  : _config = config ?? EventPipelineConfig(),
        _service = serviceChannel ?? EventPipelineServiceChannel(),
        _events = eventManager ?? EventManager(),
        _media = mediaStore ?? EventMediaStore(),
        _compositor = compositor ?? PlatformFrameCompositor(),
        _openDb = openDb ?? EventPipelineDb.openDefault,
        _printFn = printFn;

  final EventPipelineConfig _config;
  final EventManager _events;
  final EventMediaStore _media;
  final FrameCompositor _compositor;
  final Future<EventPipelineDb?> Function() _openDb;
  final EventPrintFn? _printFn;
  final EventPipelineServiceChannel _service;

  static EventPipelineRunner? _instance;

  /// Process-wide runner, or null before the first [ensureStarted].
  static EventPipelineRunner? get instance => _instance;

  @visibleForTesting
  static void resetInstanceForTests() {
    _instance?.stop();
    _instance = null;
  }

  EventPipelineDb? _db;
  EventPipelineLedger? _ledger;
  EventPipelineQueue? _queue;
  EventFrameCache? _frames;
  AiJobWorker? _ai;
  FrameJobWorker? _frame;
  PrintJobWorker? _print;
  EventMirrorWorker? _mirror;

  /// Latest resolved settings. Workers read through this getter rather than
  /// capturing a snapshot, so a settings change reaches the *next* job without
  /// disturbing the frozen chain already on each item.
  EventPipelineSettings _settings = const EventPipelineSettings(
    pipelineEnabled: false,
    offlineMode: false,
    aiEnabled: false,
    frameEnabled: false,
    autoPrint: false,
    defaultCopies: 1,
    printSize: 's4x6',
    qualityFactor: 1.0,
    mirrorEnabled: false,
    scanFolders: EventPipelineSettings.defaultScanFolders,
  );

  bool _running = false;
  FrameCacheStatus _frameStatus = const FrameCacheStatus(
    total: 0,
    cached: 0,
    selectedIsCached: false,
  );

  bool get isRunning => _running;

  /// Whether the event's frame artwork is on disk and framing can run offline.
  ///
  /// Surfaced so a station can warn **before** a batch is queued rather than
  /// deferring four hundred items one at a time.
  FrameCacheStatus get frameStatus => _frameStatus;
  EventPipelineSettings get settings => _settings;
  EventPipelineLedger? get ledger => _ledger;
  EventPipelineQueue? get queue => _queue;
  EventFrameCache? get frames => _frames;
  EventMirrorWorker? get mirror => _mirror;

  /// Starts the workers if the pipeline is on, or stops them if it is not.
  ///
  /// Called on entering any station, so toggling the setting takes effect
  /// without a restart.
  Future<bool> ensureStarted() async {
    // The whole pipeline is device-local storage and native channels.
    if (kIsWeb) return false;

    _settings = await _resolveSettings();
    if (!_settings.pipelineEnabled) {
      stop();
      return false;
    }
    if (_running) return true;

    final db = _db ?? await _openDb();
    if (db == null) {
      AppLogger.warning('Event pipeline: storage unavailable, not starting');
      return false;
    }
    _db = db;
    _wire(db);
    _startWorkers();
    _instance = this;
    _running = true;
    // Download the overlays while the link is up. Without this the frame cache
    // exists but is always empty, and every frame job defers forever.
    unawaited(refreshFrames());
    return true;
  }

  /// Fetches the frame catalogue and downloads any overlay not yet on disk.
  ///
  /// Needs WAN, so it belongs at station entry rather than mid-import. Failure
  /// is not fatal: [FrameCacheStatus] simply reports what is actually cached.
  Future<FrameCacheStatus> refreshFrames() async {
    final frames = _frames;
    if (frames == null) return _frameStatus;
    if (!_settings.frameEnabled) return _frameStatus;
    final eventId = await _events.getEventId();
    if (eventId == null || eventId.isEmpty) return _frameStatus;
    _frameStatus = await frames.refresh(
      eventId: eventId,
      selectedFrameId: _settings.frameId,
    );
    AppLogger.debug('Event frames: ${_frameStatus.summary}');
    return _frameStatus;
  }

  Future<EventPipelineSettings> _resolveSettings() async {
    return _config.resolve(
      defaults: EventPipelineDefaults(
        photoMode: await _events.getPhotoModeOverride() ?? 'BOTH',
        frameCount: await _events.getFrameCount(),
      ),
    );
  }

  void _wire(EventPipelineDb db) {
    final ledger = _ledger ??= EventPipelineLedger(db: db);
    final queue = _queue ??= EventPipelineQueue(db: db);
    final frames = _frames ??= EventFrameCache(db: db, mediaStore: _media);

    _ai ??= AiJobWorker(
      queue: queue,
      ledger: ledger,
      mediaStore: _media,
      settings: () => _settings,
    );
    _frame ??= FrameJobWorker(
      queue: queue,
      ledger: ledger,
      frameCache: frames,
      mediaStore: _media,
      compositor: _compositor,
      settings: () => _settings,
    );
    final printFn = _printFn;
    if (printFn != null) {
      _print ??= PrintJobWorker(
        queue: queue,
        ledger: ledger,
        mediaStore: _media,
        printFn: printFn,
        settings: () => _settings,
      );
    }
    _mirror ??= EventMirrorWorker(
      db: db,
      ledger: ledger,
      mediaStore: _media,
      enabled: () => _settings.mirrorEnabled,
    );
  }

  /// Raises or drops the foreground service to match what is outstanding.
  ///
  /// Only shown while there is work: an idle notification is noise, and Android
  /// increasingly penalises services that hold one without cause.
  Future<void> syncServiceState() async {
    final queue = _queue;
    if (queue == null) return;
    var open = 0;
    for (final kind in EventPipelineStep.order) {
      open += (await queue.counts(kind)).open;
    }
    if (open > 0) {
      await _service.start(status: '$open photos in the queue');
    } else {
      await _service.stop();
    }
  }

  void _startWorkers() {
    // Framing and printing are local and cheap to poll. AI and the mirror both
    // touch the network, so they tick slower — a venue link is shared with the
    // guests, and 3,000 items would otherwise hammer it.
    _frame?.start(interval: const Duration(seconds: 3));
    _print?.start(interval: const Duration(seconds: 3));
    _ai?.start(interval: const Duration(seconds: 15));
    _mirror?.start(interval: const Duration(seconds: 20));
  }

  void stop() {
    unawaited(_service.stop());
    _ai?.stop();
    _frame?.stop();
    _print?.stop();
    _mirror?.stop();
    _running = false;
    if (identical(_instance, this)) _instance = null;
  }

  /// Re-reads settings without restarting, for a live config change.
  Future<void> refreshSettings() async {
    _settings = await _resolveSettings();
  }

  /// Freezes the chain onto each item and enqueues its first step.
  ///
  /// This is the commit point the selection grid and the capture confirm both
  /// call. The steps are resolved **once**, here, so a later settings change
  /// cannot alter work already in flight.
  Future<int> queueItems(Iterable<String> mediaIds) async {
    final ledger = _ledger;
    final queue = _queue;
    if (ledger == null || queue == null) return 0;

    final steps = _settings.resolveSteps();
    var queued = 0;
    for (final mediaId in mediaIds) {
      final item = await ledger.markSelected(mediaId, steps);
      if (item == null) continue;
      queued++;

      final first = item.currentStep;
      if (first != null) {
        await queue.enqueue(
          kind: first,
          mediaId: mediaId,
          eventId: item.eventId,
          payload: <String, dynamic>{'copies': _settings.defaultCopies},
        );
      }
      // Mirroring is best-effort and never gates the local chain.
      if (_settings.mirrorEnabled) {
        await _mirror?.enqueueItem(mediaId);
      }
    }
    // Queued work must survive the operator locking the phone.
    await syncServiceState();
    return queued;
  }

  /// Queues another print of an item's finished output.
  ///
  /// Reprint is another copy of **whatever the finished output is** — the framed
  /// version if there is one, else the AI result, else the imported photo. It
  /// deliberately does not re-run a stage: the operator wants another print of
  /// what they can see, not a fresh generation that might come out different
  /// (spec §8).
  Future<bool> reprint(String mediaId) async {
    final ledger = _ledger;
    final queue = _queue;
    if (ledger == null || queue == null) return false;

    final item = await ledger.findById(mediaId);
    if (item == null) return false;
    // Nothing to reprint if no derivative was ever produced.
    if (await ledger.bestRenditionForPrint(mediaId) == null) return false;

    await queue.enqueue(
      kind: EventPipelineStep.print,
      mediaId: mediaId,
      eventId: item.eventId,
      payload: <String, dynamic>{'copies': _settings.defaultCopies},
    );
    await ledger.setStage(mediaId, MediaStage.printing);
    await syncServiceState();
    return true;
  }

  /// Removes an item from the event: its jobs, its renditions, its row and its
  /// files.
  ///
  /// The files go too. A 3,000-frame event is roughly 4 GB of derivatives, so an
  /// item removed from the queue that leaves its images behind is a disk leak
  /// with no way to find it again.
  Future<bool> removeItem(String mediaId) async {
    final ledger = _ledger;
    final queue = _queue;
    if (ledger == null || queue == null) return false;

    final item = await ledger.findById(mediaId);
    if (item == null) return false;

    await queue.deleteFor(mediaId);
    for (final rendition in await ledger.renditionsFor(mediaId)) {
      await _media.delete(rendition.path);
    }
    await ledger.deleteItem(mediaId);
    await syncServiceState();
    return true;
  }

  /// Deletes everything this event holds locally: rows, jobs and files.
  ///
  /// A 3,000-frame event is roughly 4 GB of derivatives, so without a purge a
  /// box does three events and fills its disk (spec §9C). Scoped to one event
  /// by design — `event_id` on every row is exactly what makes this a single
  /// delete rather than an archaeology exercise.
  ///
  /// Deliberately says nothing about whether it is *safe* to run. It must not
  /// destroy unprinted or unmirrored work, and deciding that is the caller's
  /// job — see [purgeBlockers].
  Future<int> purgeEvent(String eventId) async {
    final ledger = _ledger;
    final queue = _queue;
    if (ledger == null || queue == null) return 0;

    final items = await ledger.listPage(limit: 100000, eventId: eventId);
    for (final item in items) {
      await queue.deleteFor(item.id);
      await ledger.deleteItem(item.id);
    }
    await _media.purgeEvent(eventId);
    await syncServiceState();
    return items.length;
  }

  /// Reasons this event should not be purged yet, in words an operator can act
  /// on. Empty means nothing would be lost.
  ///
  /// Checked rather than assumed: the cleanup is the part with teeth, and
  /// running it over work that has not printed destroys the event.
  Future<List<String>> purgeBlockers(String eventId) async {
    final ledger = _ledger;
    if (ledger == null) return const <String>[];
    final counts = await ledger.stageCounts(eventId: eventId);
    var unfinished = 0;
    for (final entry in counts.entries) {
      if (entry.key == MediaStage.done || entry.key == MediaStage.failed) {
        continue;
      }
      unfinished += entry.value;
    }
    return <String>[
      if (unfinished > 0)
        '$unfinished ${unfinished == 1 ? 'photo has' : 'photos have'} not '
            'finished yet',
    ];
  }

  /// Runs every local stage to completion — the console's "run now".
  Future<void> drainAll() async {
    await _frame?.drainUntilIdle();
    await _print?.drainUntilIdle();
    await syncServiceState();
  }
}
