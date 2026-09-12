import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/event_pipeline/event_frame.dart';
import '../../models/event_pipeline/event_pipeline_settings.dart';
import '../../models/event_pipeline/event_readiness.dart';
import '../../models/event_pipeline/printer_consumables.dart';
import '../../services/direct_ptp_camera_service.dart';
import '../../services/event_manager.dart';
import '../../services/event_pipeline/capture/event_capture_coordinator.dart';
import '../../services/event_pipeline/event_frame_cache.dart';
import '../../services/event_pipeline/event_pipeline_config.dart';
import '../../services/event_pipeline/event_pipeline_db.dart';
import '../../services/event_pipeline/event_pipeline_runner.dart';
import '../../services/event_pipeline/event_media_store.dart';
import '../../services/event_pipeline/event_pipeline_stats.dart';
import '../../services/event_pipeline/event_pipeline_sync.dart';
import '../../services/event_pipeline/ingest/event_storage_channel.dart';
import '../../services/event_pipeline/printer_status_reader.dart';
import '../../utils/event_pipeline_capabilities.dart';
import '../../utils/logger.dart';

/// The hub: readiness, counts, and three ways out.
///
/// The screen an operator can leave open all night.
///
/// On the event box the numbers come from the local replica, so they still
/// move when the venue link is down. On web they come from the shared ZenAI
/// ledger. The one network call that is not the ledger — the event settings
/// sync — is deliberately **not** awaited before the screen paints.
class EventHubViewModel extends ChangeNotifier {
  EventHubViewModel({
    EventPipelineRunner? runner,
    EventPipelineConfig? config,
    EventManager? events,
    EventPipelineSync? sync,
    EventPipelineStatsReader? stats,
    PrinterStatusReader? printer,
    EventStorageChannel? storage,
    EventMediaStore? mediaStore,
    DirectPtpCameraService? camera,
    EventCaptureCoordinator? capture,
    Future<EventPipelineDb?> Function()? openDb,
    Duration refreshInterval = const Duration(seconds: 4),
    Duration hardwareWindow = const Duration(seconds: 15),
    int Function()? nowMs,
  })  : _runner = runner ?? EventPipelineRunner.instance ?? EventPipelineRunner(),
        _config = config ?? EventPipelineConfig(),
        _events = events ?? EventManager(),
        _stats = stats ?? EventPipelineStatsReader(),
        _printer = printer ?? PrinterStatusReader(),
        _storage = storage ?? EventStorageChannel(),
        _media = mediaStore ?? EventMediaStore(),
        _camera = camera ?? DirectPtpCameraService(),
        _capture = capture ??
            EventCaptureCoordinator(
              camera: camera ?? DirectPtpCameraService(),
              runner: runner ?? EventPipelineRunner.instance,
              events: events,
              mediaStore: mediaStore,
            ),
        _openDb = openDb ?? EventPipelineDb.openDefault,
        _refreshInterval = refreshInterval,
        _hardwareWindow = hardwareWindow,
        _nowMs = nowMs ?? _defaultNowMs {
    _sync = sync ??
        EventPipelineSync(
          config: _config,
          events: _events,
          frameCache: _buildFrameCache,
        );
  }

  final EventPipelineRunner _runner;
  final EventPipelineConfig _config;
  final EventManager _events;
  final EventPipelineStatsReader _stats;
  final PrinterStatusReader _printer;
  final EventStorageChannel _storage;
  final EventMediaStore _media;
  final DirectPtpCameraService _camera;
  final EventCaptureCoordinator _capture;
  final Future<EventPipelineDb?> Function() _openDb;
  final Duration _refreshInterval;

  /// How long the hub keeps looking for hardware after entering the event.
  ///
  /// Discovery is a **bounded window, not a poll.** Entering an event is when
  /// an operator is plugging things in and watching the rows, so for this long
  /// the camera and printer are re-checked on every tick. After it the hub
  /// stops asking entirely: enumerating USB and querying the printer every few
  /// seconds all night is contention the Amlogic box does not need, and neither
  /// changes on its own.
  ///
  /// [recheckHardware] reopens the window, which is the only thing that does.
  final Duration _hardwareWindow;
  final int Function() _nowMs;
  late final EventPipelineSync _sync;

  static int _defaultNowMs() => DateTime.now().millisecondsSinceEpoch;

  /// When the current discovery window opened. Null once it has closed.
  int? _windowOpenedAtMs;
  bool _rechecking = false;
  String? _cameraNameCache;
  PrinterConsumables? _printerCache;
  FrameCacheStatus? _frameCache;
  int? _freeBytesCache;

  Timer? _timer;
  bool _disposed = false;

  String? _eventName;
  String? _eventTagline;
  EventPipelineSettings? _settings;
  EventSyncStatus _syncStatus = const EventSyncStatus.never();
  EventPipelineStats _counters = const EventPipelineStats();
  EventReadinessReport? _readiness;
  bool _syncing = false;

  String? get eventName => _eventName;
  String? get eventTagline => _eventTagline;
  EventPipelineSettings? get settings => _settings;
  EventSyncStatus get syncStatus => _syncStatus;
  EventPipelineStats get counters => _counters;
  EventReadinessReport? get readiness => _readiness;
  bool get isSyncing => _syncing;

  /// True while the hub is still actively looking for hardware.
  bool get isCheckingHardware => _windowOpenedAtMs != null || _rechecking;

  List<ReadinessRow> get readinessRows => _readiness?.rows ?? const [];
  bool get canImport => _readiness?.canImport ?? false;
  bool get canCapture => _readiness?.canCapture ?? false;
  String? get importBlockedReason =>
      _readiness?.importBlockedReason ?? EventReadiness.waitingForSettings;
  String? get captureBlockedReason =>
      _readiness?.captureBlockedReason ?? EventReadiness.waitingForSettings;
  String get headline => _readiness?.headline ?? 'Checking…';

  /// Paint what is already known, then sync in the background.
  Future<void> start() async {
    // Idempotent, so re-entering the hub does not stack timers.
    await _runner.ensureStarted();
    await _loadEvent();
    _syncStatus = await _sync.status();
    // Entering the event opens the discovery window.
    _windowOpenedAtMs = _nowMs();
    await refresh(probeHardware: true);

    // Awaited, but nothing is waiting on start(): the provider cascades into it
    // and returns the model immediately, and refresh() above has already
    // notified. So the hub is on screen before this line runs, which is the
    // whole of §3A — "not a blocking fetch before the hub appears".
    await resync();
    _timer = Timer.periodic(_refreshInterval, (_) => unawaited(refresh()));
  }

  /// Opens the native viewfinder for as long as the operator wants it.
  ///
  /// Returns how many photos the session queued. Each one was queued as it was
  /// accepted, not at the end — this count is the tally, not the commit.
  Future<int> capture() async {
    if (!canCapture) return 0;
    final queued = await _capture.runSession();
    // Whatever landed is in the ledger now, so the counters are stale.
    await refresh();
    return queued;
  }

  /// Re-fetches the event config, for the tap on the sync row.
  ///
  /// An operator who changed something on the backend needs to know whether
  /// this device has it yet, and this is how they find out.
  Future<void> resync() async {
    if (_syncing) return;
    _syncing = true;
    _notify();
    try {
      _syncStatus = await _sync.sync();
      await _loadEvent();
    } catch (e, st) {
      // A sync that throws must not take the hub down with it — the readiness
      // block exists precisely to report this state.
      AppLogger.error('Event sync failed', error: e, stackTrace: st);
    } finally {
      _syncing = false;
      // A sync is the moment an operator is setting the event up, so look at
      // the hardware properly rather than waiting out the interval.
      await refresh(probeHardware: true);
    }
  }

  /// Re-reads counters and readiness. Local only; never touches the network.
  ///
  /// Pass [probeHardware] to force a fresh look at the camera, printer, frames
  /// and disk; otherwise they are re-read only once [_hardwareInterval] has
  /// passed. The counters are read every time — they are what actually moves.
  Future<void> refresh({bool probeHardware = false}) async {
    final settings = await _config.resolve(
      defaults: EventPipelineDefaults(
        photoMode: await _events.getPhotoModeOverride() ?? 'BOTH',
        frameCount: await _events.getFrameCount(),
      ),
    );
    final counters = await _stats.read();
    await _refreshHardware(settings, force: probeHardware);
    final caps = EventPipelineCapabilities.ofPlatform();
    final readiness = EventReadiness.evaluate(EventReadinessInput(
      settings: settings,
      hasSyncedOnce: _syncStatus.hasSyncedOnce,
      syncIsFresh: _syncStatus.isFresh,
      syncedAtMs: _syncStatus.syncedAtMs,
      syncError: _syncStatus.error,
      cameraName: _cameraNameCache,
      printer: _printerCache,
      frames: _syncStatus.frames ?? _frameCache,
      freeBytes: _freeBytesCache,
      queuePaused: counters.queuePaused,
      inFlight: counters.inFlight,
      importCapable: caps.canImport,
      captureCapable: caps.canCapture,
      // The last sync reaching ZenAI is the honest signal for whether AI jobs
      // will run: a link that carried the config is a link that carries a
      // generation, and there is no separate reachability check to pay for.
      online: _syncStatus.isFresh,
    ));

    _settings = settings;
    _counters = counters;
    _readiness = readiness;
    _notify();
  }

  /// Probes the hardware while the discovery window is open, then stops.
  Future<void> _refreshHardware(
    EventPipelineSettings settings, {
    required bool force,
  }) async {
    final opened = _windowOpenedAtMs;
    if (!force) {
      if (opened == null) return;
      if (_nowMs() - opened >= _hardwareWindow.inMilliseconds) {
        // The window has closed. Nothing looks again until Recheck.
        _windowOpenedAtMs = null;
        return;
      }
    }
    _cameraNameCache = await _cameraName();
    _printerCache = await _printer.read();
    _frameCache = await _frameStatus(settings);
    _freeBytesCache = await _freeBytes();
  }

  /// Asks Android for permission to use the printer, then re-checks.
  ///
  /// The only way out of [PrinterReadiness.needsPermission]: the native side
  /// opens the printer as part of granting, and a status read cannot succeed
  /// until something has.
  Future<void> allowPrinter() async {
    if (_rechecking) return;
    _rechecking = true;
    _notify();
    try {
      await _printer.requestPermission();
      _windowOpenedAtMs = _nowMs();
      await refresh(probeHardware: true);
    } finally {
      _rechecking = false;
      _notify();
    }
  }

  /// Looks for the camera and printer again, for another window.
  ///
  /// The operator's control for "I have just plugged it in", and the only way
  /// back once the window has closed. Also the answer to a row that has gone
  /// stale: the hub stops asking, so a camera unplugged after the window would
  /// otherwise read connected until someone checked.
  Future<void> recheckHardware() async {
    if (_rechecking) return;
    _rechecking = true;
    _windowOpenedAtMs = _nowMs();
    _notify();
    try {
      await refresh(probeHardware: true);
    } finally {
      _rechecking = false;
      _notify();
    }
  }

  Future<void> _loadEvent() async {
    final event = await _events.readBoundEvent();
    _eventName = event?.name ?? await _events.getEventName();
    _eventTagline = event?.description;
  }

  /// Model of whatever is on the USB bus, without connecting to it.
  ///
  /// Probing rather than connecting matters: opening a PTP session to answer a
  /// readiness row would take the camera out of the photographer's hands.
  Future<String?> _cameraName() async {
    try {
      final device = await _camera.probeDevice();
      if (device == null) return null;
      final product = device.product?.trim() ?? '';
      return product.isEmpty ? device.deviceName : product;
    } catch (e) {
      AppLogger.debug('Camera probe failed: $e');
      return null;
    }
  }

  /// Free space where the derivatives actually land, not on the system volume.
  Future<int?> _freeBytes() async {
    try {
      final root = await _media.resolveRoot();
      if (root == null) return null;
      return await _storage.freeBytes(root.path);
    } catch (e) {
      AppLogger.debug('Free space unreadable: $e');
      return null;
    }
  }

  Future<EventFrameCache?> _buildFrameCache() async {
    final db = await _openDb();
    // Shares this screen's media store: overlays and derivatives live under one
    // root, and the free-space row would otherwise be measuring a different
    // disk from the one the frames land on.
    return db == null ? null : EventFrameCache(db: db, mediaStore: _media);
  }

  Future<FrameCacheStatus?> _frameStatus(EventPipelineSettings settings) async {
    if (!settings.frameEnabled) return null;
    try {
      final eventId = await _events.getEventId();
      if (eventId == null) return null;
      final cache = await _buildFrameCache();
      if (cache == null) return null;
      return await cache.status(
        eventId: eventId,
        selectedFrameId: settings.frameId,
      );
    } catch (e) {
      AppLogger.debug('Frame status unreadable: $e');
      return null;
    }
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
