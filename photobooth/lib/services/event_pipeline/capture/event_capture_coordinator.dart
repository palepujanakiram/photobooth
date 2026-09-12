import 'dart:async';

import '../../../utils/logger.dart';
import '../../direct_ptp_camera_service.dart';
import '../../event_manager.dart';
import '../event_media_store.dart';
import '../event_pipeline_runner.dart';
import '../ingest/image_downscaler.dart';
import '../ingest/ingest_worker.dart';
import '../ingest/platform_image_downscaler.dart';
import 'direct_ptp_capture_source.dart';
import 'event_capture_source.dart';

/// What happened to one accepted frame, in words the capture screen shows.
class CaptureCommitOutcome {
  const CaptureCommitOutcome({required this.queued, required this.message});

  final bool queued;
  final String message;
}

/// Runs the operator's capture session and queues what comes back.
///
/// There is no Dart capture screen. The native screen owns the whole
/// interaction — live view, shutter, and the retake/confirm review — because
/// live view draws into a `SurfaceView`, a hardware overlay plane, and pulling
/// it into Flutter would cost a copy per frame on a box that already needs
/// Impeller disabled.
///
/// So this is not a view model. It launches that screen, listens for the frames
/// the operator accepts while it is still up, and commits each one. The screen
/// never closes between shots: confirm queues the photo, says so, and returns
/// to live view.
class EventCaptureCoordinator {
  EventCaptureCoordinator({
    DirectPtpCameraService? camera,
    EventPipelineRunner? runner,
    EventManager? events,
    EventMediaStore? mediaStore,
    ImageDownscaler? downscaler,
  })  : _camera = camera ?? DirectPtpCameraService(),
        _injectedRunner = runner,
        _events = events ?? EventManager(),
        _media = mediaStore ?? EventMediaStore(),
        _downscaler = downscaler ?? PlatformImageDownscaler();

  final DirectPtpCameraService _camera;
  final EventManager _events;
  final EventMediaStore _media;
  final ImageDownscaler _downscaler;

  final EventPipelineRunner? _injectedRunner;
  EventPipelineRunner? _fallbackRunner;

  /// Resolved when it is used, never at construction.
  ///
  /// `EventPipelineRunner.instance` is set by whichever runner started, and
  /// this coordinator is built inside the hub view model's initializer list —
  /// before anything has started, so the static is still null there. Capturing
  /// it at that moment bound this to a *second*, unstarted runner whose ledger
  /// stayed null forever, and every accepted frame reported "Storage
  /// unavailable — not queued" while the hub's own counters worked fine.
  EventPipelineRunner get _runner =>
      _injectedRunner ??
      EventPipelineRunner.instance ??
      (_fallbackRunner ??= EventPipelineRunner());

  StreamSubscription<DirectPtpShot>? _subscription;

  /// Every frame committed in the session that just ran, newest last.
  final List<String> _queuedIds = <String>[];

  List<String> get queuedIds => List.unmodifiable(_queuedIds);

  /// Opens the native viewfinder and queues each accepted frame until the
  /// operator closes it.
  ///
  /// Returns how many photos were queued. Never throws: a capture session that
  /// fails leaves the operator on the hub with a message, not a crash.
  Future<int> runSession() async {
    _queuedIds.clear();
    _camera.listenForAcceptedShots();

    // Subscribed before **anything** is awaited. The stream is a broadcast, so
    // a frame accepted before the listener attaches is dropped silently, and
    // every line below yields to the event loop.
    final eventId = _events.getEventId();
    _subscription = _camera.acceptedShots.listen((shot) {
      // Not awaited: the native screen has already returned to live view and
      // the photographer may be framing the next shot. Queueing behind them is
      // the point of handing it over rather than blocking on it.
      unawaited(_commit(shot, eventId));
    });
    try {
      // Cheap and idempotent, and safely after the subscription: a coordinator
      // reached before anything started the pipeline would otherwise queue
      // nothing and only say so once per frame.
      await _runner.ensureStarted();
      await _camera.runCaptureSession(await _requestForEvent());
    } catch (e, st) {
      AppLogger.error('Capture session failed', error: e, stackTrace: st);
    } finally {
      await _subscription?.cancel();
      _subscription = null;
    }
    return _queuedIds.length;
  }

  /// Registers one accepted frame and queues it.
  ///
  /// Runs through [IngestWorker], the same path a card import takes, so a
  /// captured frame gets identical dedupe, downscale, thumbnail and ledger
  /// handling rather than a second implementation free to drift.
  Future<CaptureCommitOutcome> _commit(
    DirectPtpShot shot,
    Future<String?> eventId,
  ) async {
    final outcome = await _commitInner(shot, eventId);
    // The screen said "Added to queue" optimistically when it handed the frame
    // over, which is right almost always. Correct it only when it was wrong —
    // an operator should never be told a photo landed when it did not.
    if (!outcome.queued) {
      await _camera.postCaptureMessage(outcome.message);
    }
    return outcome;
  }

  Future<CaptureCommitOutcome> _commitInner(
    DirectPtpShot shot,
    Future<String?> eventId,
  ) async {
    final ledger = _runner.ledger;
    if (ledger == null) {
      return const CaptureCommitOutcome(
        queued: false,
        message: 'Storage unavailable — not queued',
      );
    }
    try {
      final source = CapturedShotSource(CapturedShot(
        originalPath: shot.originalPath,
        previewPath: shot.displayPath,
        capturedAtMs: shot.capturedAtMs == 0
            ? DateTime.now().millisecondsSinceEpoch
            : shot.capturedAtMs,
        width: shot.widthPx,
        height: shot.heightPx,
        bytes: shot.bytes,
      ));
      final candidates = await source.listAll();
      if (candidates.isEmpty) {
        return const CaptureCommitOutcome(
          queued: false,
          message: 'The photo was not where the camera said',
        );
      }
      final report = await IngestWorker(
        ledger: ledger,
        mediaStore: _media,
        downscaler: _downscaler,
      ).import(
        source,
        candidates,
        settings: _runner.settings,
        eventId: await eventId,
      );
      if (report.mediaIds.isEmpty) {
        return CaptureCommitOutcome(
          queued: false,
          message: report.duplicates > 0
              ? 'Already in the queue'
              : 'Could not store the photo',
        );
      }
      await _runner.queueItems(report.mediaIds);
      _queuedIds.addAll(report.mediaIds);
      return const CaptureCommitOutcome(
        queued: true,
        message: 'Added to queue',
      );
    } catch (e, st) {
      AppLogger.error('Capture commit failed', error: e, stackTrace: st);
      return const CaptureCommitOutcome(
        queued: false,
        message: 'Could not queue the photo',
      );
    }
  }

  /// The operator's session, wearing the event's name and colours.
  Future<DirectPtpCaptureRequest> _requestForEvent() async {
    try {
      final event = await _events.readBoundEvent();
      final skin = event?.chrome.skin;
      return DirectPtpCaptureSource.requestFor(
        title: event?.name,
        subtitle: event?.description,
        ink: skin?.ink,
        accent: skin?.bannerFrom,
        background: skin?.bannerTo,
        continuous: true,
      );
    } catch (e) {
      AppLogger.debug('Could not dress the viewfinder: $e');
      // Chrome is dressing; a capture screen in default colours still works.
      return DirectPtpCaptureSource.requestFor(continuous: true);
    }
  }

  /// Model of whatever is on the USB bus, without connecting to it.
  Future<String?> cameraName() =>
      DirectPtpCaptureSource(service: _camera).cameraName();
}
