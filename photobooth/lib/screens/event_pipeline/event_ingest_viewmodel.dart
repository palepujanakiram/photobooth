import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/event_pipeline/event_pipeline_settings.dart';
import '../../services/event_manager.dart';
import '../../services/event_pipeline/event_media_store.dart';
import '../../services/event_pipeline/event_pipeline_config.dart';
import '../../services/event_pipeline/event_pipeline_db.dart';
import '../../services/event_pipeline/event_pipeline_ledger.dart';
import '../../services/event_pipeline/event_pipeline_runner.dart';
import '../../services/event_pipeline/ingest/card_detect_channel.dart';
import '../../services/event_pipeline/ingest/event_storage_channel.dart';
import '../../services/event_pipeline/ingest/image_downscaler.dart';
import '../../services/event_pipeline/ingest/ingest_diff.dart';
import '../../services/event_pipeline/ingest/ingest_source.dart';
import '../../services/event_pipeline/ingest/ingest_worker.dart';
import '../../services/event_pipeline/ingest/media_store_ingest_source.dart';
import '../../services/event_pipeline/ingest/platform_image_downscaler.dart';
import '../../utils/logger.dart';

/// Where the station is in the import cycle.
enum IngestPhase {
  /// Nothing readable is inserted.
  noCard,

  /// Cards are mounted and the operator has not chosen one yet.
  ///
  /// The first state of every import. **Nothing is read until they tap a row**:
  /// a multi-slot reader can hold several cards, so "the card" is not something
  /// the app can assume, and a scan burns I/O on a card the operator may not
  /// have meant — on a slow box, competing with whatever the queue is already
  /// doing (spec §5).
  pickVolume,

  /// A card is mounted but MediaStore is still indexing it.
  scanning,

  /// Scan settled; the operator picks what to import.
  review,

  importing,

  /// Import finished — the "safe to remove card" state, which is the point of
  /// the whole feature.
  complete,

  /// Mounted but not MediaStore-indexed, so it cannot be read.
  unreadable,

  /// The runtime media permission has not been granted.
  needsPermission,
}

/// Drives the SD import station.
///
/// Owns the full cycle: detect a card, wait for the media scanner to settle,
/// diff against the ledger, let the operator select, then import one image at a
/// time. Nothing here holds image bytes — only metadata and ids.
class EventIngestViewModel extends ChangeNotifier {
  EventIngestViewModel({
    EventStorageChannel? storage,
    CardDetectChannel? cardDetect,
    EventPipelineConfig? config,
    EventManager? eventManager,
    EventMediaStore? mediaStore,
    ImageDownscaler? downscaler,
    MediaStoreSettleWatcher? settleWatcher,
    EventPipelineRunner? runner,
    Future<EventPipelineDb?> Function()? openDb,
    Future<PermissionStatus> Function()? requestMediaPermission,
    Future<PermissionStatus> Function()? readMediaPermission,
  })  : _storage = storage ?? EventStorageChannel(),
        _cardDetect = cardDetect ?? CardDetectChannel(),
        _config = config ?? EventPipelineConfig(),
        _events = eventManager ?? EventManager(),
        _mediaStore = mediaStore ?? EventMediaStore(),
        _downscaler = downscaler ?? PlatformImageDownscaler(),
        _settleWatcher = settleWatcher ?? MediaStoreSettleWatcher(),
        _runner = runner ?? EventPipelineRunner.instance ?? EventPipelineRunner(),
        _openDb = openDb ?? EventPipelineDb.openDefault,
        _requestPermission =
            requestMediaPermission ?? (() => Permission.photos.request()),
        _readPermission =
            readMediaPermission ?? (() => Permission.photos.status);

  final EventStorageChannel _storage;
  final CardDetectChannel _cardDetect;
  final EventPipelineConfig _config;
  final EventManager _events;
  final EventMediaStore _mediaStore;
  final ImageDownscaler _downscaler;
  final MediaStoreSettleWatcher _settleWatcher;
  final EventPipelineRunner _runner;
  final Future<EventPipelineDb?> Function() _openDb;
  final Future<PermissionStatus> Function() _requestPermission;
  final Future<PermissionStatus> Function() _readPermission;

  StreamSubscription<CardEvent>? _cardSubscription;
  IngestWorker? _worker;
  MediaStoreIngestSource? _source;

  IngestPhase _phase = IngestPhase.noCard;
  List<ExternalVolume> _volumes = const <ExternalVolume>[];
  ExternalVolume? _volume;
  IngestScanResult? _scan;
  EventPipelineSettings? _settings;
  String? _eventId;
  String? _error;
  int _scanningCount = 0;
  IngestProgress? _progress;
  IngestReport? _report;
  bool _busy = false;

  /// Set by the card-detect stream, read by the import loop's [shouldContinue].
  ///
  /// This is what turns a pulled card into one clean stop instead of a failure
  /// per remaining photo — see screens spec §9A.
  bool _cardRemoved = false;

  /// How many photos the interrupted run was asked to import, so the operator
  /// can be told "imported 50 of 400" rather than just "50".
  int _importTotal = 0;

  /// Tier-1 keys of the items the operator has ticked.
  final Set<String> _selected = <String>{};

  /// Folders outside the configured scan roots the operator opted into.
  final Set<String> _extraFolders = <String>{};

  IngestPhase get phase => _phase;

  /// Every mounted volume, shown even when there is only one. Consistency beats
  /// saving a tap, and it keeps "which card am I looking at" on screen.
  List<ExternalVolume> get volumes => _volumes;

  /// The card the operator chose, once they have.
  ExternalVolume? get volume => _volume;
  IngestScanResult? get scan => _scan;
  EventPipelineSettings? get settings => _settings;
  String? get errorMessage => _error;
  bool get isBusy => _busy;
  int get scanningCount => _scanningCount;
  IngestProgress? get progress => _progress;
  IngestReport? get report => _report;
  int get importTotal => _importTotal;

  /// True when the last run stopped because the card went away. The remaining
  /// photos are untouched on the card and their rows were rolled back, so
  /// "scan again to continue" is truthful.
  bool get stoppedOnCardRemoval => _report?.stoppedOnCardRemoval ?? false;
  Set<String> get extraFolders => Set.unmodifiable(_extraFolders);

  List<IngestCandidate> get candidates => _scan?.newCandidates ?? const [];
  int get alreadyImported => _scan?.alreadyImported ?? 0;
  int get selectedCount => _selected.length;
  bool get hasSelection => _selected.isNotEmpty;

  bool isSelected(IngestCandidate c) => _selected.contains(c.sourceRef);
  bool isFolderIncluded(IngestFolderSummary f) =>
      f.selectedByDefault || _extraFolders.contains(f.folder);

  /// The chain each imported photo will run, for the footer preview.
  List<String> get resolvedSteps => _settings?.resolveSteps() ?? const [];

  Future<void> start() async {
    // Starting the workers here is what makes an import actually go anywhere.
    // Idempotent, so re-entering the station does not stack timers.
    await _runner.ensureStarted();
    await _loadContext();
    _cardSubscription = _cardDetect.events().listen(_onCardEvent);
    await refresh();
  }

  Future<void> _loadContext() async {
    _eventId = await _events.getEventId();
    _settings = await _config.resolve(
      defaults: EventPipelineDefaults(
        photoMode: await _events.getPhotoModeOverride() ?? 'BOTH',
        frameCount: await _events.getFrameCount(),
      ),
    );
    final db = await _openDb();
    if (db != null) {
      _worker = IngestWorker(
        ledger: EventPipelineLedger(db: db),
        mediaStore: _mediaStore,
        downscaler: _downscaler,
      );
    }
    notifyListeners();
  }

  void _onCardEvent(CardEvent event) {
    if (event.isRemoval) {
      _cardRemoved = true;
      // Mid-import the loop stops itself at the next check and the report says
      // why. Wiping the screen here instead would replace an honest "imported
      // 50 of 400 — reinsert and scan again" with a blank "insert a card".
      if (_phase == IngestPhase.importing) return;
      unawaited(_reconcileVolumes());
      return;
    }
    _cardRemoved = false;
    // An insert is only a hint that something appeared. The volume may not be
    // mounted yet, and even once mounted MediaStore has not indexed it. Nothing
    // is scanned either way — the operator still chooses.
    unawaited(_reconcileVolumes());
  }

  /// Re-lists volumes after the reader changed, keeping the operator's place.
  ///
  /// Pulling the *other* card of a two-slot reader must not throw away a scan
  /// in progress, so the chosen card is only abandoned when it is the one that
  /// actually went.
  Future<void> _reconcileVolumes() async {
    if (_busy) return;
    List<ExternalVolume> volumes;
    try {
      volumes = await _storage.listVolumes();
    } catch (e) {
      AppLogger.debug('Volume re-list failed: $e');
      return;
    }
    _volumes = volumes;

    final chosen = _volume;
    if (chosen == null) {
      // On the picker, or nothing chosen: the list is the whole screen.
      if (_phase != IngestPhase.complete) {
        _setPhase(volumes.isEmpty ? IngestPhase.noCard : IngestPhase.pickVolume);
      }
      notifyListeners();
      return;
    }
    if (volumes.any((v) => v.uuid == chosen.uuid)) {
      // Some other slot changed; the card being worked on is still seated.
      notifyListeners();
      return;
    }
    _volume = null;
    _source = null;
    _scan = null;
    _selected.clear();
    if (_phase != IngestPhase.complete) {
      _setPhase(volumes.isEmpty ? IngestPhase.noCard : IngestPhase.pickVolume);
    }
    notifyListeners();
  }

  /// Re-lists what is mounted and returns to the picker.
  ///
  /// Deliberately does **not** scan. Discovering a card and reading one are now
  /// separate actions, so an operator can seat a second card without the app
  /// starting work on it.
  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      if (!await _ensurePermission()) return;
      _volumes = await _storage.listVolumes();
      _volume = null;
      _source = null;
      _scan = null;
      _selected.clear();
      _setPhase(_volumes.isEmpty ? IngestPhase.noCard : IngestPhase.pickVolume);
    } catch (e, st) {
      AppLogger.error('Ingest refresh failed', error: e, stackTrace: st);
      _error = 'Could not read the card reader.';
      _setPhase(IngestPhase.noCard);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Reads the card the operator tapped. The only path that touches a card.
  Future<void> selectVolume(ExternalVolume volume) async {
    if (_busy) return;
    _busy = true;
    _error = null;
    _volume = volume;
    notifyListeners();
    try {
      if (!volume.isUsable) {
        // Mounted but not indexed — distinct from an empty card, and the
        // operator needs to be told which it is.
        _setPhase(IngestPhase.unreadable);
        return;
      }
      await _scanVolume(volume);
    } catch (e, st) {
      AppLogger.error('Ingest scan failed', error: e, stackTrace: st);
      _error = 'Could not read the card.';
      _setPhase(IngestPhase.pickVolume);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Re-reads the card already chosen — the "Scan again" action.
  Future<void> rescan() async {
    final volume = _volume;
    if (volume == null) {
      await refresh();
      return;
    }
    await selectVolume(volume);
  }

  /// Leaves a chosen card and goes back to the list.
  Future<void> backToVolumes() async {
    _report = null;
    await refresh();
  }

  Future<bool> _ensurePermission() async {
    final status = await _readPermission();
    if (status.isGranted || status.isLimited) return true;
    final requested = await _requestPermission();
    if (requested.isGranted || requested.isLimited) return true;
    _setPhase(IngestPhase.needsPermission);
    return false;
  }

  /// Waits for the media scanner before trusting a count.
  ///
  /// Required, not defensive: a card mounts with **zero** MediaStore rows and
  /// indexes over roughly 11 s per 260 files. Scanning on the mount broadcast
  /// reports "0 new photos" on a full card.
  Future<void> _scanVolume(ExternalVolume volume) async {
    final settings = _settings;
    final worker = _worker;
    if (settings == null || worker == null) return;

    final scanFolders = settings.scanFolders;
    final source = MediaStoreIngestSource(
      volume: volume,
      scanFolders: const <String>[],
      channel: _storage,
    );
    _source = source;

    _setPhase(IngestPhase.scanning);
    await _settleWatcher.awaitSettled(
      count: () async => (await source.listAll()).length,
      onProgress: (current, settled) {
        _scanningCount = current;
        notifyListeners();
      },
    );

    final result = await worker.scan(
      source,
      scanFolders: scanFolders,
      extraFolders: _extraFolders,
    );
    _scan = result;
    _selected
      ..clear()
      ..addAll(result.newCandidates.map((c) => c.sourceRef));
    _setPhase(IngestPhase.review);
  }

  void toggleItem(IngestCandidate candidate) {
    if (!_selected.remove(candidate.sourceRef)) {
      _selected.add(candidate.sourceRef);
    }
    notifyListeners();
  }

  void selectAll() {
    _selected
      ..clear()
      ..addAll(candidates.map((c) => c.sourceRef));
    notifyListeners();
  }

  void selectNone() {
    _selected.clear();
    notifyListeners();
  }

  /// Widens or narrows the scan by folder, then re-diffs.
  Future<void> toggleFolder(IngestFolderSummary folder) async {
    if (folder.selectedByDefault) return;
    if (!_extraFolders.remove(folder.folder)) {
      _extraFolders.add(folder.folder);
    }
    final source = _source;
    final worker = _worker;
    final settings = _settings;
    if (source == null || worker == null || settings == null) return;

    _busy = true;
    notifyListeners();
    try {
      final result = await worker.scan(
        source,
        scanFolders: settings.scanFolders,
        extraFolders: _extraFolders,
      );
      _scan = result;
      _selected
        ..clear()
        ..addAll(result.newCandidates.map((c) => c.sourceRef));
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Imports the ticked items, writing a print-ready derivative for each.
  Future<void> importSelected() async {
    final worker = _worker;
    final source = _source;
    final settings = _settings;
    if (worker == null || source == null || settings == null || _busy) return;

    final chosen = candidates.where(isSelected).toList();
    if (chosen.isEmpty) {
      _error = 'Select at least one photo to import.';
      notifyListeners();
      return;
    }

    _busy = true;
    _error = null;
    _importTotal = chosen.length;
    _progress = IngestProgress(
      done: 0,
      total: chosen.length,
      imported: 0,
      duplicates: 0,
      failed: 0,
    );
    _setPhase(IngestPhase.importing);

    try {
      final report = await worker.import(
        source,
        chosen,
        settings: settings,
        eventId: _eventId,
        onProgress: (p) {
          _progress = p;
          notifyListeners();
        },
        shouldContinue: () async =>
            _cardRemoved ? IngestReport.cardRemovedReason : null,
      );
      _report = report;
      // Freeze each item's chain and enqueue its first step. Settings are read
      // once, here, so a later change cannot alter work already in flight.
      await _runner.queueItems(report.mediaIds);
      _setPhase(IngestPhase.complete);
    } catch (e, st) {
      AppLogger.error('Import failed', error: e, stackTrace: st);
      _error = 'Import failed. Nothing was lost — try again.';
      _setPhase(IngestPhase.review);
    } finally {
      _busy = false;
      _progress = null;
      notifyListeners();
    }
  }

  /// Leaves the "safe to remove" state and returns to the card list.
  Future<void> done() async {
    _report = null;
    _scan = null;
    _cardRemoved = false;
    _selected.clear();
    await refresh();
  }

  void _setPhase(IngestPhase phase) {
    _phase = phase;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_cardSubscription?.cancel());
    _cardSubscription = null;
    super.dispose();
  }
}
