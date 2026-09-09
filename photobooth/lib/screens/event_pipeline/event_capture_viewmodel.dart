import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/event_pipeline/event_pipeline_settings.dart';
import '../../models/event_pipeline/media_rendition.dart';
import '../../services/event_manager.dart';
import '../../services/event_pipeline/capture/direct_ptp_capture_source.dart';
import '../../services/event_pipeline/capture/event_capture_source.dart';
import '../../services/event_pipeline/event_media_store.dart';
import '../../services/event_pipeline/event_pipeline_runner.dart';
import '../../services/event_pipeline/ingest/image_downscaler.dart';
import '../../services/event_pipeline/ingest/ingest_worker.dart';
import '../../services/event_pipeline/ingest/platform_image_downscaler.dart';
import '../../utils/logger.dart';

/// A frame that has been committed, for the recent strip.
class RecentShot {
  const RecentShot({required this.mediaId, required this.name, this.thumbnail});

  final String mediaId;
  final String name;
  final File? thumbnail;
}

/// Where the capture screen is.
enum CapturePhase {
  /// Waiting for the operator to open the viewfinder.
  ready,

  /// The native viewfinder is up: live view, shutter, and its own review.
  shooting,

  /// The accepted frame is being registered and queued.
  committing,

  /// No camera on the bus.
  noCamera,
}

/// Tethered capture straight into the event queue.
///
/// **The viewfinder is the native screen.** It owns live view, the shutter and
/// the retake/accept review, because live view draws into a `SurfaceView` —
/// a hardware overlay plane, and the cheapest path Android has. This model
/// runs what happens either side of it: opening the viewfinder, and committing
/// what comes back.
///
/// **Accepting is the commit point.** A frame that comes back is registered and
/// queued with the steps frozen at that moment. A retake never reaches here at
/// all — the native review discards it — so a photographer can fire freely and
/// only what they accept becomes work (spec §6).
class EventCaptureViewModel extends ChangeNotifier {
  EventCaptureViewModel({
    EventCaptureSource? source,
    EventPipelineRunner? runner,
    EventManager? events,
    EventMediaStore? mediaStore,
    ImageDownscaler? downscaler,
    int recentLimit = 5,
  })  : _source = source ?? DirectPtpCaptureSource(),
        _runner = runner ?? EventPipelineRunner.instance ?? EventPipelineRunner(),
        _events = events ?? EventManager(),
        _media = mediaStore ?? EventMediaStore(),
        _downscaler = downscaler ?? PlatformImageDownscaler(),
        _recentLimit = recentLimit;

  final EventCaptureSource _source;
  final EventPipelineRunner _runner;
  final EventManager _events;
  final EventMediaStore _media;
  final ImageDownscaler _downscaler;
  final int _recentLimit;

  CapturePhase _phase = CapturePhase.noCamera;
  String? _cameraName;
  String? _error;
  String? _eventId;
  final List<RecentShot> _recent = <RecentShot>[];

  CapturePhase get phase => _phase;
  String? get cameraName => _cameraName;

  String? get errorMessage => _error;
  bool get isBusy =>
      _phase == CapturePhase.shooting || _phase == CapturePhase.committing;
  bool get canShoot => _phase == CapturePhase.ready;

  /// The last few committed frames.
  ///
  /// Matters more than it looks: a photographer needs to see frames landing to
  /// trust the thing is working. Without it a silent failure looks identical to
  /// a working booth until someone checks the queue.
  List<RecentShot> get recentShots => List.unmodifiable(_recent);

  Future<void> start() async {
    await _runner.ensureStarted();
    _eventId = await _events.getEventId();
    await _dressViewfinder();
    await refreshCamera();
  }

  /// Puts the event's name and colours on the native viewfinder.
  ///
  /// The screen a photographer looks at all evening should belong to the event
  /// they are shooting, not read as a generic booth. The skin already arrives
  /// with the event, so this costs nothing but passing it along.
  Future<void> _dressViewfinder() async {
    final source = _source;
    if (source is! DirectPtpCaptureSource) return;
    try {
      final event = await _events.readBoundEvent();
      final skin = event?.chrome.skin;
      source.request = DirectPtpCaptureSource.requestFor(
        title: event?.name,
        subtitle: event?.description,
        ink: skin?.ink,
        accent: skin?.bannerFrom,
        background: skin?.bannerTo,
      );
    } catch (e) {
      // Chrome is dressing; a capture screen in default colours still works.
      AppLogger.debug('Could not dress the viewfinder: $e');
    }
  }

  Future<void> refreshCamera() async {
    _cameraName = await _source.cameraName();
    final connected = _cameraName?.trim().isNotEmpty ?? false;
    if (!connected) {
      _phase = CapturePhase.noCamera;
    } else if (_phase == CapturePhase.noCamera) {
      _phase = CapturePhase.ready;
    }
    notifyListeners();
  }

  /// Opens the native viewfinder and commits whatever comes back.
  ///
  /// One call covers the whole interaction: live view, the shutter, and the
  /// retake/accept review all happen inside it. A retake never returns here —
  /// the native review loops back to live view on its own — so anything this
  /// receives is a frame the operator accepted.
  Future<bool> openViewfinder() async {
    if (!canShoot) return false;
    _phase = CapturePhase.shooting;
    _error = null;
    notifyListeners();
    CapturedShot? shot;
    try {
      shot = await _source.shoot();
    } catch (e, st) {
      AppLogger.error('Capture failed', error: e, stackTrace: st);
      _error = 'Capture failed. Check the cable and try again.';
      _phase = CapturePhase.ready;
      notifyListeners();
      return false;
    }
    if (shot == null) {
      // Cancelled, or the camera returned nothing. Neither is an error worth
      // shouting about: the operator closed the viewfinder.
      _phase = CapturePhase.ready;
      notifyListeners();
      return false;
    }
    return _commit(shot);
  }

  /// Registers the frame and queues it, with the chain frozen at this moment.
  ///
  /// Runs through [IngestWorker], the same path a card import takes, so a
  /// captured frame gets identical dedupe, downscale, thumbnail and ledger
  /// handling rather than a second implementation that can drift.
  Future<bool> _commit(CapturedShot shot) async {
    final ledger = _runner.ledger;
    if (ledger == null) {
      _error = 'Storage is unavailable, so the photo was not queued.';
      _phase = CapturePhase.ready;
      notifyListeners();
      return false;
    }
    _phase = CapturePhase.committing;
    _error = null;
    notifyListeners();
    try {
      final source = CapturedShotSource(shot);
      final worker = IngestWorker(
        ledger: ledger,
        mediaStore: _media,
        downscaler: _downscaler,
      );
      final candidates = await source.listAll();
      if (candidates.isEmpty) {
        _error = 'The captured file was not where the camera said it was.';
        _phase = CapturePhase.ready;
        return false;
      }
      final report = await worker.import(
        source,
        candidates,
        settings: _settings(),
        eventId: _eventId,
      );
      if (report.mediaIds.isEmpty) {
        _error = report.duplicates > 0
            ? 'That photo is already in the queue.'
            : 'Could not store the photo.';
        _phase = CapturePhase.ready;
        return false;
      }
      await _runner.queueItems(report.mediaIds);
      await _addRecent(report.mediaIds.first, shot);
      _phase = CapturePhase.ready;
      return true;
    } catch (e, st) {
      AppLogger.error('Capture confirm failed', error: e, stackTrace: st);
      _error = 'Could not queue the photo. Nothing was lost — try again.';
      _phase = CapturePhase.ready;
      return false;
    } finally {
      notifyListeners();
    }
  }

  EventPipelineSettings _settings() => _runner.settings;

  Future<void> _addRecent(String mediaId, CapturedShot shot) async {
    final ledger = _runner.ledger;
    File? thumb;
    if (ledger != null) {
      for (final r in await ledger.renditionsFor(mediaId)) {
        if (r.kind == RenditionKind.thumb) {
          thumb = await _media.getFile(r.path);
          break;
        }
      }
    }
    _recent.insert(
      0,
      RecentShot(mediaId: mediaId, name: shot.fileName, thumbnail: thumb),
    );
    if (_recent.length > _recentLimit) _recent.removeRange(_recentLimit, _recent.length);
  }

  @override
  void dispose() {
    unawaited(_source.dispose());
    super.dispose();
  }
}
