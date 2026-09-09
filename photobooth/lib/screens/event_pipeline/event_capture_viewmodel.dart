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
  /// Waiting on the shutter.
  ready,

  /// The shutter is open, or the frame is coming back over USB.
  shooting,

  /// A frame is on screen awaiting Confirm or Retake.
  reviewing,

  /// Confirm is running — registering and queueing.
  committing,

  /// No camera on the bus.
  noCamera,
}

/// Tethered capture straight into the event queue.
///
/// **Confirm is the commit point.** It registers the item and queues it with
/// the steps frozen at that moment. Retake writes nothing at all — no ledger
/// row, no derivative, no job — so a photographer can fire freely and only what
/// they accept becomes work (spec §6).
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
  CapturedShot? _pending;
  String? _error;
  String? _eventId;
  final List<RecentShot> _recent = <RecentShot>[];

  CapturePhase get phase => _phase;
  String? get cameraName => _cameraName;

  /// The frame awaiting Confirm or Retake. Nothing has been written for it.
  CapturedShot? get pendingShot => _pending;

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
    await refreshCamera();
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

  /// Fires the shutter and holds the result for review.
  Future<void> shoot() async {
    if (!canShoot) return;
    _phase = CapturePhase.shooting;
    _error = null;
    notifyListeners();
    try {
      final shot = await _source.shoot();
      if (shot == null) {
        _error = 'The camera did not return a photo. Check it is awake.';
        _phase = CapturePhase.ready;
        return;
      }
      _pending = shot;
      _phase = CapturePhase.reviewing;
    } catch (e, st) {
      AppLogger.error('Capture failed', error: e, stackTrace: st);
      _error = 'Capture failed. Check the cable and try again.';
      _phase = CapturePhase.ready;
    } finally {
      notifyListeners();
    }
  }

  /// Discards the frame. Writes nothing at all.
  ///
  /// The file the camera stack left behind goes too: a retake the operator
  /// rejected must not quietly fill the disk, and it has no ledger row to find
  /// it by later.
  Future<void> retake() async {
    final shot = _pending;
    _pending = null;
    _phase = CapturePhase.ready;
    notifyListeners();
    if (shot == null) return;
    await _deleteQuietly(shot.originalPath);
    final preview = shot.previewPath;
    if (preview != null && preview != shot.originalPath) {
      await _deleteQuietly(preview);
    }
  }

  /// Registers the frame and queues it, with the chain frozen at this moment.
  ///
  /// Runs through [IngestWorker], the same path a card import takes, so a
  /// captured frame gets identical dedupe, downscale, thumbnail and ledger
  /// handling rather than a second implementation that can drift.
  Future<bool> confirm() async {
    final shot = _pending;
    final ledger = _runner.ledger;
    if (shot == null || ledger == null || _phase == CapturePhase.committing) {
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
        _phase = CapturePhase.reviewing;
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
        _phase = CapturePhase.reviewing;
        return false;
      }
      await _runner.queueItems(report.mediaIds);
      await _addRecent(report.mediaIds.first, shot);
      _pending = null;
      _phase = CapturePhase.ready;
      return true;
    } catch (e, st) {
      AppLogger.error('Capture confirm failed', error: e, stackTrace: st);
      _error = 'Could not queue the photo. Nothing was lost — try again.';
      _phase = CapturePhase.reviewing;
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

  Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      AppLogger.debug('Could not delete a retaken frame: $e');
    }
  }

  @override
  void dispose() {
    unawaited(_source.dispose());
    super.dispose();
  }
}
