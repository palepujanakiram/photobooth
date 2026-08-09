import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:camera_native_details/camera_native_details.dart';
import 'package:uvccamera/uvccamera.dart';
import 'photo_capture_camera_picker_screen.dart';
import 'photo_capture_pose_setup_helpers.dart';
import 'photo_capture_preview_rotation.dart';
import 'photo_capture_camera_error_helpers.dart';
import 'photo_capture_uvc_device_helpers.dart';
import 'photo_capture_uvc_feed_phase.dart';
import 'photo_capture_uvc_reconnect_helpers.dart';
import 'photo_capture_uvc_raster_capture.dart';
import 'photo_capture_uvc_take_picture_helpers.dart';
import 'photo_capture_uvc_shutter_helpers.dart';
import 'photo_capture_hdmi_pose_helpers.dart';
import 'photo_capture_sidecar_helpers.dart';
import 'photo_capture_desktop_body.dart';
import 'photo_capture_body_phase.dart';
import 'photo_capture_view_aspect.dart';
import 'photo_capture_view_handlers.dart';
import 'photo_capture_exit_handlers.dart';
import 'photo_capture_gallery_handlers.dart';
import 'photo_capture_phone_upload_sheet.dart';
import 'photo_capture_idle_policy.dart';
import 'photo_capture_flashback_auto_helpers.dart';
import 'photo_capture_view_layout.dart';
import 'photo_capture_view_scaffold.dart';
import 'photo_capture_viewmodel.dart';
import 'photo_model.dart';
import 'photo_image_from_xfile_io.dart' if (dart.library.html) 'photo_image_from_xfile_web.dart' as photo_image;
import '../../models/strip_models.dart';
import '../../utils/app_device_type.dart';
import '../../utils/app_runtime_config.dart';
import '../../utils/app_strings.dart';
import '../../utils/capture_session_kind.dart';
import '../../utils/classic_capture_intent.dart';
import '../../utils/classic_one_shot_fsm.dart';
import '../../utils/classic_shot_mode.dart';
import '../../utils/classic_pose_mode_helpers.dart';
import '../../utils/classic_strip_scrub_helpers.dart';
import '../../utils/classic_strip_scrub_coordinator.dart';
import '../../utils/constants.dart';
import '../../utils/device_classifier.dart';
import '../../utils/image_helper.dart';
import '../../utils/kiosk_page_route.dart';
import '../../utils/logger.dart';
import '../../utils/route_args.dart';
import '../../utils/surprise_me_helpers.dart';
import '../../utils/uvc_capture_config.dart';
import '../fotoflashback/fotoflashback_filter_view.dart';
import '../theme_selection/theme_model.dart';
import '../../services/app_settings_manager.dart';
import '../../services/error_reporting/error_reporting_manager.dart';
import '../../services/uvc_device_event_hub.dart';
import '../../services/uvc_session_coordinator.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/centered_max_width.dart';
import '../../views/widgets/classic_scrub_progress_dots.dart';
import '../../views/widgets/flashback_review_hold_banner.dart';
import '../../views/widgets/sidecar_live_preview.dart';
import 'photo_capture_rotation_screen.dart';
import '../../services/hardware_key_service.dart';

class PhotoCaptureScreen extends StatefulWidget {
  const PhotoCaptureScreen({
    super.key,
    this.sessionKind = CaptureSessionKind.fotoZen,
    this.captureArgs,
  });

  /// Immutable POSE flow — set at construction, never re-derived.
  final CaptureSessionKind sessionKind;

  /// Classic strip theme / remount progress. Ignored for [CaptureSessionKind.fotoZen].
  final CaptureRouteArgs? captureArgs;

  @override
  State<PhotoCaptureScreen> createState() => _PhotoCaptureScreenState();
}

class _PhotoCaptureScreenState extends State<PhotoCaptureScreen>
    with WidgetsBindingObserver {
  late CaptureViewModel _captureViewModel;
  StreamSubscription<HardwareKeyEvent>? _hardwareKeySub;
  bool _hardwareKeysEnabled = false;
  UvcCameraDevice? _uvcDevice;
  UvcCameraController? _uvcController;
  bool _uvcInitializing = false;
  String? _uvcError;
  bool _showCaptureFlash = false;
  StreamSubscription<UvcCameraButtonEvent>? _uvcButtonSub;
  StreamSubscription<UvcCameraStatusEvent>? _uvcStatusSub;
  StreamSubscription<UvcCameraErrorEvent>? _uvcErrorSub;
  StreamSubscription<UvcCameraDeviceEvent>? _uvcDeviceEventsSub;
  DateTime? _lastUvcShutterAt;
  bool _uvcShutterKeysEnabled = false;
  bool _uvcCaptureInFlight = false;
  /// Opaque HDMI mask from countdown end through still assign (status LCD).
  bool _uvcHdmiStillMaskArmed = false;
  UvcFeedPhase _uvcPhase = UvcFeedPhase.live;
  final GlobalKey _uvcPreviewBoundaryKey = GlobalKey();
  bool _uvcOpeningController = false;
  Timer? _uvcReconnectTimer;
  Timer? _uvcWarmupTimer;
  Timer? _uvcSessionRecycleTimer;
  Timer? _uvcIdleSleepTimer;
  bool _uvcFeedAsleep = false;
  bool _uvcLifecyclePaused = false;
  DateTime? _uvcShutterGraceUntil;
  DateTime? _uvcIgnoreDisconnectUntil;
  int _uvcAutoReconnectAttempts = 0;
  bool _uvcReconnectInFlight = false;
  Timer? _uvcTvProbeTimer;
  Timer? _uvcEntryProbeTimer;
  Future<void> _captureInitOp = Future<void>.value();
  bool _skipUvcForCameraXSession = false;
  DateTime? _uvcPreviewReadyAt;
  /// Last Canon LV ensure reported an active Pi hold (shorten HDMI mask).
  bool _canonLvHolding = false;
  Duration _uvcPreviewWarmupPeriod = UvcCaptureConfig.previewWarmupPeriod;
  int _uvcPreviewGeneration = 0;
  DateTime? _uvcLastUiCaptureEndedAt;
  Future<void> _uvcOp = Future<void>.value();

  bool _prefillApplied = false;
  Timer? _poseIdleTimer;
  Timer? _poseLoadingWatchdog;
  Timer? _captureWatchdog;
  bool _navigatingAwayFromCapture = false;
  bool _appInForeground = true;

  CaptureScreenIdleInput _poseIdleInput(CaptureViewModel viewModel) {
    return CaptureScreenIdleInput(
      isNavigatingAway: _navigatingAwayFromCapture,
      isCapturing: viewModel.isCapturing,
      isUploading: viewModel.isUploading,
      isCountingDown: viewModel.isCountingDown,
      appInForeground: _appInForeground,
      isWaitingForPhoneUpload: viewModel.isWaitingForPhoneUpload,
    );
  }

  void _stopPoseIdleTimer() {
    _poseIdleTimer?.cancel();
    _poseIdleTimer = null;
  }

  void _syncPoseIdleTimer(CaptureViewModel viewModel) {
    if (!captureScreenIdleTimerShouldRun(_poseIdleInput(viewModel))) {
      _stopPoseIdleTimer();
      return;
    }
    if (_poseIdleTimer?.isActive == true) return;
    _armPoseIdleTimer();
  }

  void _armPoseIdleTimer() {
    _stopPoseIdleTimer();
    _poseIdleTimer = Timer(AppConstants.kCaptureScreenIdleResetDuration, () {
      _safeUnawaited(
        _onPoseIdleTimeout(),
        label: 'POSE idle timeout failed',
      );
    });
  }

  void _notePoseUserActivity() {
    if (_navigatingAwayFromCapture) return;
    if (!captureScreenIdleTimerShouldRun(_poseIdleInput(_captureViewModel))) {
      return;
    }
    _armPoseIdleTimer();
  }

  void _onCaptureViewModelStateChanged() {
    if (!mounted) return;
    _syncPoseIdleTimer(_captureViewModel);
    _syncCaptureWatchdog(_captureViewModel);
    // Classic 1-shot is a linear FSM — never drive it from VM notify storms
    // (UVC normalize / reopen was restarting countdowns forever).
    if (widget.sessionKind.isClassicFourShot) {
      _maybeAdvanceFlashbackAutoChain();
    } else if (widget.sessionKind.isClassicOneShot) {
      _oneShotOnViewModelTick();
    }
  }

  void _syncCaptureWatchdog(CaptureViewModel viewModel) {
    if (viewModel.isCapturing || _uvcCaptureInFlight) {
      if (_captureWatchdog?.isActive == true) return;
      _armCaptureWatchdog();
      return;
    }
    _cancelCaptureWatchdog();
  }

  void _armCaptureWatchdog() {
    _captureWatchdog?.cancel();
    final deviceType = _captureViewModel.deviceType;
    final seconds = kioskShouldTryUvcBeforeCameraX(deviceType) ? 22 : 48;
    _captureWatchdog = Timer(Duration(seconds: seconds), _onCaptureWatchdogFired);
  }

  void _cancelCaptureWatchdog() {
    _captureWatchdog?.cancel();
    _captureWatchdog = null;
  }

  void _onCaptureWatchdogFired() {
    if (!mounted) return;
    if (!_captureViewModel.isCapturing && !_uvcCaptureInFlight) return;
    AppLogger.error('POSE capture watchdog — forcing abort');
    _captureViewModel.forceAbortCapture();
    _clearUvcTransientCaptureUi();
    if (_uvcPhase == UvcFeedPhase.capturing) {
      _uvcPhase = UvcFeedPhase.error;
    }
    setState(() {
      _uvcError ??=
          'Capture took too long. Tap Capture to retry or use Gallery.';
    });
  }

  void _onScrubProgressChanged() {
    if (mounted) setState(() {});
  }

  void _cancelFlashbackAutoTimers() {
    _flashbackReviewTimer?.cancel();
    _flashbackReviewTimer = null;
    _flashbackReviewTick?.cancel();
    _flashbackReviewTick = null;
    _flashbackReviewEndsAt = null;
    _flashbackReviewPhotoId = null;
    if (_flashbackReviewSecondsLeft != null && mounted) {
      setState(() => _flashbackReviewSecondsLeft = null);
    } else {
      _flashbackReviewSecondsLeft = null;
    }
  }

  bool get _flashbackReviewHoldActive => flashbackReviewHoldAlreadyScheduled(
        timerActive: _flashbackReviewTimer?.isActive == true,
        hasDeadline: _flashbackReviewEndsAt != null,
      );

  void _maybeAdvanceFlashbackAutoChain() {
    if (!mounted) return;
    // 1-shot never enters this chain — see [_oneShotDispatch].
    if (!widget.sessionKind.isClassicFourShot) return;
    // Accept has detached the still but not finished retake/resume yet.
    if (_flashbackAcceptingShot) return;

    final vm = _captureViewModel;
    final total = _classicShotCap;
    final photo = vm.capturedPhoto;

    // Already counting down for this still — never re-arm (that froze "… 8").
    if (photo != null &&
        _flashbackReviewEndsAt != null &&
        _flashbackReviewPhotoId == photo.id) {
      return;
    }

    if (shouldScheduleFlashbackAutoAccept(
      isFlashbackMultiShot: true,
      stripFinishing: _stripFinishing,
      navigatingAway: _navigatingAwayFromCapture,
      hasCapturedPhoto: photo != null,
      isCapturing: vm.isCapturing || _uvcCaptureInFlight,
      autoAcceptAlreadyScheduled: _flashbackReviewHoldActive,
    )) {
      _scheduleFlashbackAutoAccept();
      return;
    }
    if (shouldAutoStartFlashbackCountdown(
      isFlashbackMultiShot: true,
      stripFinishing: _stripFinishing,
      navigatingAway: _navigatingAwayFromCapture,
      hasCapturedPhoto: photo != null,
      isCountingDown: vm.isCountingDown || _flashbackCountdownStarting,
      isCapturing: vm.isCapturing || _uvcCaptureInFlight || _uvcHdmiStillMaskArmed,
      acceptedShotCount: _stripShots.length,
      multiShotTotal: total,
      cameraReadyForCapture: _flashbackCameraReady,
      awaitGuestStart: _awaitGuestStartClassic,
      isSingleShot: false,
      singleShotCapturesStarted: _singleShotCapturesStarted,
    )) {
      unawaited(_startFlashbackAutoCountdown());
    }
  }

  // ---------------------------------------------------------------------------
  // Classic 1-shot linear FSM (USB webcam must not loop)
  // ---------------------------------------------------------------------------

  ClassicOneShotPhase _oneShotPhase = ClassicOneShotPhase.idle;

  void _oneShotOnViewModelTick() {
    if (!widget.sessionKind.isClassicOneShot) return;
    final photo = _captureViewModel.capturedPhoto;
    if (photo != null &&
        !_captureViewModel.isCapturing &&
        !_uvcCaptureInFlight &&
        (_oneShotPhase == ClassicOneShotPhase.counting ||
            _oneShotPhase == ClassicOneShotPhase.capturing)) {
      _oneShotDispatch(ClassicOneShotEvent.stillReady);
      return;
    }
    // Only the initial idle→counting auto-start comes from camera-ready.
    if (_oneShotPhase == ClassicOneShotPhase.idle &&
        !_awaitGuestStartClassic &&
        _flashbackCameraReady &&
        photo == null &&
        !_captureViewModel.isCountingDown &&
        !_flashbackCountdownStarting) {
      _oneShotDispatch(ClassicOneShotEvent.cameraReady);
    }
  }

  void _oneShotDispatch(ClassicOneShotEvent event) {
    if (!widget.sessionKind.isClassicOneShot || !mounted) return;
    final next = classicOneShotTransition(phase: _oneShotPhase, event: event);
    if (next == null) {
      AppLogger.debug(
        'Classic 1-shot ignore event=$event phase=$_oneShotPhase',
      );
      return;
    }
    AppLogger.debug('Classic 1-shot $_oneShotPhase → $next ($event)');
    _oneShotPhase = next;
    switch (next) {
      case ClassicOneShotPhase.counting:
        unawaited(_oneShotRunCountdownAndCapture());
      case ClassicOneShotPhase.captured:
        unawaited(_oneShotAcceptToLooks());
      case ClassicOneShotPhase.needsGuest:
        _resetClassicOneShotForGuestRetry();
      case ClassicOneShotPhase.idle:
      case ClassicOneShotPhase.capturing:
      case ClassicOneShotPhase.finishing:
      case ClassicOneShotPhase.done:
        break;
    }
  }

  /// After a failed capture/encode, drop partial strip state so Capture takes a
  /// fresh still. Leaving [_stripShots] or the VM photo made guestCapture jump
  /// straight back to accept → looks (USB/sidecar encode timeout loop).
  void _resetClassicOneShotForGuestRetry() {
    _awaitGuestStartClassic = true;
    _singleShotCapturesStarted = 0;
    _flashbackCountdownStarting = false;
    _stripFinishing = false;
    _navigatingAwayFromCapture = false;
    _uvcHdmiStillMaskArmed = false;
    if (_stripShots.isNotEmpty || _stripScrubFutures.isNotEmpty) {
      _stripShots.clear();
      _stripScrubFutures.clear();
      ClassicStripScrubCoordinator.instance.reset();
    }
    if (_captureViewModel.capturedPhoto != null) {
      unawaited(_captureViewModel.clearCapturedPhotoAwaitingSession());
    }
    if (mounted) setState(() {});
  }

  Future<void> _oneShotRunCountdownAndCapture() async {
    if (!widget.sessionKind.isClassicOneShot) return;
    if (_oneShotPhase != ClassicOneShotPhase.counting) return;
    // Only short-circuit when this countdown already produced a still — never
    // when leftover strip/VM state remains from a failed accept.
    if (_stripShots.isEmpty && _captureViewModel.capturedPhoto != null) {
      _oneShotDispatch(ClassicOneShotEvent.stillReady);
      return;
    }
    if (_stripShots.isNotEmpty) {
      AppLogger.warning(
        'Classic 1-shot clearing stale strip before retry capture',
      );
      _stripShots.clear();
      _stripScrubFutures.clear();
      ClassicStripScrubCoordinator.instance.reset();
    }
    _singleShotCapturesStarted = 1;
    _awaitGuestStartClassic = false;
    _flashbackCountdownStarting = true;
    final seconds = captureCountdownSecondsForMode(isFlashbackMultiShot: true);
    try {
      if (_isUsingUvc) {
        await _captureViewModel.captureWithCountdown(
          () async {
            if (_oneShotPhase != ClassicOneShotPhase.counting) return;
            _oneShotDispatch(ClassicOneShotEvent.shutterStarted);
            await _captureUvc(_captureViewModel, source: 'classic_one_shot');
          },
          canStart: () =>
              mounted &&
              widget.sessionKind.isClassicOneShot &&
              (_oneShotPhase == ClassicOneShotPhase.counting ||
                  _oneShotPhase == ClassicOneShotPhase.capturing) &&
              _uvcReadyForCapture &&
              !_uvcCaptureInFlight &&
              _flashbackCameraReady &&
              _captureViewModel.capturedPhoto == null &&
              _stripShots.isEmpty,
          countdownSeconds: seconds,
          onCountdownFinished: _armUvcHdmiStillMask,
        );
      } else {
        _oneShotDispatch(ClassicOneShotEvent.shutterStarted);
        await _captureViewModel.capturePhotoWithCountdown(
          countdownSeconds: seconds,
        );
      }
    } finally {
      _flashbackCountdownStarting = false;
      // Countdown may have armed the HDMI mask then aborted before shutter.
      if (_captureViewModel.capturedPhoto == null && !_uvcCaptureInFlight) {
        _uvcHdmiStillMaskArmed = false;
      }
      if (mounted && widget.sessionKind.isClassicOneShot) {
        if (_captureViewModel.capturedPhoto != null) {
          _oneShotDispatch(ClassicOneShotEvent.stillReady);
        } else if (_oneShotPhase == ClassicOneShotPhase.counting ||
            _oneShotPhase == ClassicOneShotPhase.capturing) {
          AppLogger.error(
            'Classic 1-shot produced no still; phase→needsGuest',
          );
          _oneShotDispatch(ClassicOneShotEvent.captureFailed);
        }
      }
    }
  }

  Future<void> _oneShotAcceptToLooks() async {
    if (!widget.sessionKind.isClassicOneShot) return;
    if (_oneShotPhase != ClassicOneShotPhase.captured) return;
    if (_stripFinishing || _navigatingAwayFromCapture) return;
    final vm = _captureViewModel;
    final photo = vm.capturedPhoto;
    final theme = _flashbackTheme ?? ClassicCaptureIntent.peekTheme();
    if (photo == null) {
      _oneShotDispatch(ClassicOneShotEvent.captureFailed);
      return;
    }
    _cancelFlashbackAutoTimers();
    // Move to finishing immediately so a second stillReady cannot double-accept.
    _oneShotDispatch(ClassicOneShotEvent.finishStarted);
    if (_oneShotPhase != ClassicOneShotPhase.finishing) return;

    if (_stripShots.isEmpty) {
      final scrubEnabled = classicOverlayScrubEnabled(
        context.read<AppSettingsManager>().settings?.enableOsdScrub,
      );
      final Future<ClassicShotScrubResult> scrubFuture;
      if (scrubEnabled) {
        scrubFuture = ClassicStripScrubCoordinator.instance.enqueueShot(
          encodeShotDataUrl: () =>
              ImageHelper.encodeImageToBase64(photo.imageFile),
          enableScrub: true,
        );
      } else {
        scrubFuture = ImageHelper.encodeImageToBase64(photo.imageFile).then(
          (raw) => ClassicShotScrubResult(dataUrl: raw, scrubbed: false),
        );
      }
      setState(() {
        _stripShots.add(photo);
        _stripScrubFutures.add(scrubFuture);
        _multiShotTotal = 1;
        _subtitleHint = AppStrings.flashbackSingle6x4Title;
      });
    }
    if (theme == null) {
      AppLogger.error('Classic 1-shot accept missing flashbackTheme');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.flashbackFinishEncodeFailed)),
        );
      }
      _oneShotDispatch(ClassicOneShotEvent.captureFailed);
      return;
    }
    await _finishFlashbackStrip(theme);
    if (!mounted) return;
    if (_navigatingAwayFromCapture) {
      _oneShotDispatch(ClassicOneShotEvent.finished);
    } else {
      // Encode/nav failed — guest may retry; never auto-loop.
      _oneShotDispatch(ClassicOneShotEvent.captureFailed);
    }
  }

  /// Guest Capture / shutter for Classic 1-shot only.
  void _oneShotRequestGuestCapture() {
    if (!widget.sessionKind.isClassicOneShot) return;
    // If auto-start was blocked (no LV hold), try arming again before counting.
    if (!_canonLvHolding &&
        _captureViewModel.localCameraService?.isConfigured == true) {
      unawaited(() async {
        await _armCanonLiveViewForPose();
        if (!mounted) return;
        _oneShotDispatch(ClassicOneShotEvent.guestCapture);
      }());
      return;
    }
    _oneShotDispatch(ClassicOneShotEvent.guestCapture);
  }

  void _scheduleFlashbackAutoAccept() {
    final photo = _captureViewModel.capturedPhoto;
    if (photo == null) return;

    // One deadline per still — never reset to 8 on parent notify storms.
    if (_flashbackReviewEndsAt != null &&
        _flashbackReviewPhotoId == photo.id &&
        _flashbackReviewTimer?.isActive == true) {
      return;
    }

    _flashbackReviewTimer?.cancel();
    _flashbackReviewTick?.cancel();
    _flashbackReviewTick = null;

    final total = _classicShotCap;
    final hold = total == 1
        ? const Duration(milliseconds: 600)
        : AppConstants.kFlashbackShotReviewDuration;
    final endsAt = DateTime.now().add(hold);
    _flashbackReviewPhotoId = photo.id;
    _flashbackReviewEndsAt = endsAt;

    if (mounted) {
      setState(() {
        // Kept for legacy null-checks; banner reads [endsAt] directly.
        _flashbackReviewSecondsLeft =
            hold > Duration.zero ? hold.inSeconds.clamp(0, 60) : null;
      });
    } else {
      _flashbackReviewSecondsLeft =
          hold > Duration.zero ? hold.inSeconds.clamp(0, 60) : null;
    }

    _flashbackReviewTimer = Timer(hold, () {
      if (!mounted) return;
      final expectedId = _flashbackReviewPhotoId;
      _flashbackReviewTimer = null;
      _flashbackReviewEndsAt = null;
      _flashbackReviewPhotoId = null;
      if (_flashbackReviewSecondsLeft != null) {
        setState(() => _flashbackReviewSecondsLeft = null);
      }
      // Still must match the one we scheduled for (guest may have retaken).
      final current = _captureViewModel.capturedPhoto;
      if (current == null || current.id != expectedId) return;
      unawaited(_acceptFlashbackShot(_captureViewModel));
    });
  }

  Future<void> _startFlashbackAutoCountdown() async {
    // Classic 1-shot uses [_oneShotDispatch] only — never share this path.
    if (!widget.sessionKind.isClassicFourShot) return;
    if (_flashbackCountdownStarting || !mounted) return;
    if (!shouldAutoStartFlashbackCountdown(
      isFlashbackMultiShot: true,
      stripFinishing: _stripFinishing,
      navigatingAway: _navigatingAwayFromCapture,
      hasCapturedPhoto: _captureViewModel.capturedPhoto != null,
      isCountingDown: _captureViewModel.isCountingDown,
      isCapturing: _captureViewModel.isCapturing ||
          _uvcCaptureInFlight ||
          _uvcHdmiStillMaskArmed,
      acceptedShotCount: _stripShots.length,
      multiShotTotal: _classicShotCap,
      cameraReadyForCapture: _flashbackCameraReady,
      awaitGuestStart: _awaitGuestStartClassic,
      isSingleShot: false,
      singleShotCapturesStarted: _singleShotCapturesStarted,
    )) {
      return;
    }
    _awaitGuestStartClassic = false;
    _flashbackCountdownStarting = true;
    final seconds = captureCountdownSecondsForMode(isFlashbackMultiShot: true);
    try {
      if (_isUsingUvc) {
        await _captureViewModel.captureWithCountdown(
          () => _captureUvc(_captureViewModel, source: 'flashback_auto'),
          canStart: () =>
              mounted &&
              _uvcReadyForCapture &&
              !_uvcCaptureInFlight &&
              _flashbackCameraReady &&
              _captureViewModel.capturedPhoto == null,
          countdownSeconds: seconds,
          onCountdownFinished: _armUvcHdmiStillMask,
        );
      } else {
        await _captureViewModel.capturePhotoWithCountdown(
          countdownSeconds: seconds,
        );
      }
    } finally {
      _flashbackCountdownStarting = false;
      if (_captureViewModel.capturedPhoto == null && !_uvcCaptureInFlight) {
        _uvcHdmiStillMaskArmed = false;
      }
      if (mounted) _maybeAdvanceFlashbackAutoChain();
    }
  }

  void _dropLastStripShot() {
    if (_stripShots.isEmpty) return;
    _stripShots.removeLast();
    if (_stripScrubFutures.isNotEmpty) {
      _stripScrubFutures.removeLast();
    }
    ClassicStripScrubCoordinator.instance.dropLast();
    _syncFlashbackSubtitle();
  }

  Future<void> _retakeLastFlashbackShot() async {
    _cancelFlashbackAutoTimers();
    _captureViewModel.cancelCountdown();
    if (_captureViewModel.capturedPhoto != null) {
      await _handleRetake(context);
      return;
    }
    if (_stripShots.isEmpty) return;
    setState(_dropLastStripShot);
    _maybeAdvanceFlashbackAutoChain();
  }

  Future<void> _releaseCaptureHardware() async {
    _stopPoseIdleTimer();
    _cancelUvcSessionRecycleTimer();
    _cancelUvcIdleSleepTimer();
    _uvcReconnectTimer?.cancel();
    _uvcReconnectInFlight = false;
    _uvcDeviceEventsSub?.cancel();
    _uvcDeviceEventsSub = null;
    await _disposeUvcForNavigation();
    await _captureViewModel.disposeCamera();
  }

  Future<void> _exitCaptureToTerms({
    required String sessionEndContext,
    required bool endCustomerSession,
  }) async {
    if (_navigatingAwayFromCapture) return;
    _navigatingAwayFromCapture = true;
    _stopPoseIdleTimer();
    await exitCaptureScreenToTerms(
      context: context,
      isMounted: () => mounted,
      releaseCaptureHardware: _releaseCaptureHardware,
      sessionEndContext: sessionEndContext,
      endCustomerSession: endCustomerSession,
    );
  }

  Future<void> _onPoseIdleTimeout() async {
    if (!mounted || _navigatingAwayFromCapture) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(AppStrings.captureScreenIdleResetMessage),
        duration: AppConstants.kCaptureScreenIdleResetSnackDuration,
      ),
    );
    await Future<void>.delayed(AppConstants.kCaptureScreenIdleResetSnackDelay);
    if (!mounted || _navigatingAwayFromCapture) return;
    await _exitCaptureToTerms(
      sessionEndContext: 'capture_idle_timeout',
      endCustomerSession: true,
    );
  }

  bool _returnPhotoOnly = false;
  String? _subtitleHint;
  int? _multiShotTotal;
  ThemeModel? _flashbackTheme;
  final List<PhotoModel> _stripShots = <PhotoModel>[];
  /// Parallel to [_stripShots]: in-flight / completed per-shot scrub results.
  final List<Future<ClassicShotScrubResult>?> _stripScrubFutures =
      <Future<ClassicShotScrubResult>?>[];
  bool _stripFinishing = false;
  Timer? _flashbackReviewTimer;
  Timer? _flashbackReviewTick;
  DateTime? _flashbackReviewEndsAt;
  /// Photo id the current review deadline belongs to (blocks re-arm to "8").
  String? _flashbackReviewPhotoId;
  int? _flashbackReviewSecondsLeft;
  bool _flashbackCountdownStarting = false;
  /// True while a Classic still is being committed to the strip (blocks re-accept).
  bool _flashbackAcceptingShot = false;
  /// Classic 1-shot: how many auto/manual pose captures were started this visit.
  int _singleShotCapturesStarted = 0;
  /// Back from looks: live preview only until guest taps Capture / shutter.
  bool _awaitGuestStartClassic = false;
  /// FotoZen: after first countdown/shutter starts, ignore TV keys / UVC button
  /// until Retake — prevents HDMI capture-card double-fires.
  bool _fotoZenCaptureLocked = false;

  /// Classic POSE (1-shot or 4-shot). Prefer this over [_isFlashbackMultiShot].
  bool get _isClassicPose => widget.sessionKind.isClassic;

  /// Classic 4-shot strip only — never true for 1-shot (avoids remount chain).
  bool get _isFlashbackMultiShot => widget.sessionKind.isClassicFourShot;

  bool get _isFlashbackFourShot => widget.sessionKind.isClassicFourShot;

  bool get _isFlashbackSingleShot => widget.sessionKind.isClassicOneShot;

  int get _classicShotCap => widget.sessionKind.classicShotCount ?? 0;

  void _syncClassicPoseFieldsFromKind() {
    final mode = widget.sessionKind.classicShotMode;
    if (mode == null) return;
    _returnPhotoOnly = true;
    _multiShotTotal = mode.shotCount;
    _subtitleHint = classicPoseSubtitle(mode);
  }

  bool get _flashbackCameraReady {
    if (_captureViewModel.usesSidecarLivePreview) {
      return _captureViewModel.isReady;
    }
    if (!_isUsingUvc) return _captureViewModel.isReady;
    // Do NOT fold [_uvcHdmiStillMaskArmed] into captureInFlight here.
    // Mask is armed from onCountdownFinished *before* the shutter canStart
    // re-check; treating it as in-flight aborted every still (hdmi_mask_armed
    // with no capture_begin on the Pi).
    final ready = uvcHdmiPoseReadyForCountdown(
      uvcControllerReady: _uvcReadyForCapture,
      captureInFlight: _uvcCaptureInFlight,
      previewWarmupActive: _uvcPreviewWarmupActive,
      sidecarConfigured:
          _captureViewModel.localCameraService?.isConfigured == true,
      canonLvHolding: _canonLvHolding,
    );
    // Throttle — this getter is polled from the VM tick.
    final now = DateTime.now();
    if (_lastHdmiPoseReadyLogAt == null ||
        now.difference(_lastHdmiPoseReadyLogAt!) >
            const Duration(seconds: 2)) {
      _lastHdmiPoseReadyLogAt = now;
      AppLogger.info(
        '[HDMI_POSE] ready=$ready uvc=$_uvcReadyForCapture '
        'warmup=$_uvcPreviewWarmupActive lvHold=$_canonLvHolding '
        'sidecar=${_captureViewModel.localCameraService?.isConfigured == true} '
        'inFlight=$_uvcCaptureInFlight mask=$_uvcHdmiStillMaskArmed',
      );
      unawaited(
        _captureViewModel.localCameraService?.postClientEvent('pose_ready', {
          'ready': ready,
          'uvc': _uvcReadyForCapture,
          'warmup': _uvcPreviewWarmupActive,
          'lvHold': _canonLvHolding,
          'inFlight': _uvcCaptureInFlight,
          'mask': _uvcHdmiStillMaskArmed,
        }),
      );
    }
    return ready;
  }

  DateTime? _lastHdmiPoseReadyLogAt;

  void _armUvcHdmiStillMask() {
    if (_uvcHdmiStillMaskArmed) return;
    _uvcHdmiStillMaskArmed = true;
    AppLogger.info('[HDMI_POSE] HDMI still mask armed');
    unawaited(
      _captureViewModel.localCameraService?.postClientEvent('hdmi_mask_armed'),
    );
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefillApplied) return;
    _prefillApplied = true;
    // FotoZen: never adopt ModalRoute Classic args (Android TV often keeps the
    // previous `/capture` arguments when the route name matches).
    if (!widget.sessionKind.isClassic) {
      ClassicCaptureIntent.clear();
      return;
    }
    _applyClassicCaptureArgs(
      widget.captureArgs ?? ModalRoute.of(context)?.settings.arguments,
    );
  }

  /// Load Classic theme / strip progress. Mode comes only from [sessionKind].
  void _applyClassicCaptureArgs(Object? args) {
    if (!widget.sessionKind.isClassic) return;

    final captureArgs = CaptureRouteArgs.tryParse(args);
    if (captureArgs != null) {
      _returnPhotoOnly = captureArgs.returnPhotoOnly;
      _subtitleHint = captureArgs.subtitleHint;
      _flashbackTheme = captureArgs.flashbackTheme;
      _awaitGuestStartClassic = captureArgs.awaitGuestStart;
      if (captureArgs.acceptedStripShots.isNotEmpty) {
        _stripShots
          ..clear()
          ..addAll(captureArgs.acceptedStripShots);
        _captureViewModel.markAwaitingCameraRemount();
      }
    }

    _flashbackTheme ??= ClassicCaptureIntent.peekTheme();
    _syncClassicPoseFieldsFromKind();
    _syncFlashbackSubtitle();

    if (widget.sessionKind.isClassicOneShot) {
      _oneShotPhase = _awaitGuestStartClassic
          ? ClassicOneShotPhase.needsGuest
          : ClassicOneShotPhase.idle;
    }

    if (_stripShots.isEmpty) {
      ClassicStripScrubCoordinator.instance.reset();
    }

    _captureViewModel.preferStripPrintQuality = true;
    AppLogger.debug(
      'Classic POSE kind=${widget.sessionKind.name} '
      'multiShotTotal=$_multiShotTotal '
      'theme=${_flashbackTheme?.id} '
      'strip=${_stripShots.length} awaitGuest=$_awaitGuestStartClassic',
    );
    if (args is Map && args['photo'] is PhotoModel) {
      final photo = args['photo'] as PhotoModel;
      _captureViewModel.capturedPhoto = photo;
    }
  }

  void _syncFlashbackSubtitle() {
    if (_isFlashbackSingleShot) {
      _multiShotTotal = 1;
      _subtitleHint = AppStrings.flashbackSingle6x4Title;
      return;
    }
    final total = _classicShotCap;
    if (total < 1) return;
    final next = (_stripShots.length + 1).clamp(1, total);
    _subtitleHint = AppStrings.flashbackShotProgress(next, total);
  }

  Future<void> _acceptFlashbackShot(CaptureViewModel viewModel) async {
    final photo = viewModel.capturedPhoto;
    if (photo == null || _stripFinishing) {
      _cancelFlashbackAutoTimers();
      return;
    }

    // Classic 1-shot: FSM owns accept → looks (no 4-shot remount).
    if (widget.sessionKind.isClassicOneShot) {
      if (_oneShotPhase == ClassicOneShotPhase.finishing ||
          _oneShotPhase == ClassicOneShotPhase.done) {
        return;
      }
      if (_oneShotPhase != ClassicOneShotPhase.captured) {
        _oneShotPhase = ClassicOneShotPhase.captured;
      }
      await _oneShotAcceptToLooks();
      return;
    }

    final theme = _flashbackTheme ?? ClassicCaptureIntent.peekTheme();
    if (!widget.sessionKind.isClassicFourShot) return;
    if (theme == null) return;
    final total = _classicShotCap;
    if (total <= 0) return;

    // Same still accepted repeatedly → identical strip frames on look screen.
    if (_flashbackAcceptingShot) {
      AppLogger.debug('Classic 4-shot accept ignored (already accepting)');
      return;
    }
    if (_stripShots.any((p) => p.id == photo.id)) {
      AppLogger.error(
        'Classic 4-shot blocked duplicate accept of photo ${photo.id}',
      );
      _cancelFlashbackAutoTimers();
      await _resumeAfterClassicShotAccepted();
      return;
    }

    if (_stripShots.length >= total) {
      await _finishFlashbackStrip(theme);
      return;
    }

    _flashbackAcceptingShot = true;
    _cancelFlashbackAutoTimers();

    try {
      // Snapshot bytes before clearing VM / reinit (web blob XFiles go stale).
      final encodedDataUrl = await ImageHelper.encodeImageToBase64(
        photo.imageFile,
      );
      if (!mounted) return;
      if (encodedDataUrl.trim().isEmpty) {
        AppLogger.error('Classic 4-shot encode empty for photo ${photo.id}');
        await _resumeAfterClassicShotAccepted();
        return;
      }

      // Detach so notify storms cannot re-accept this still.
      viewModel.clearCapturedPhoto();

      final scrubEnabled = classicOverlayScrubEnabled(
        context.read<AppSettingsManager>().settings?.enableOsdScrub,
      );
      final scrubFuture = ClassicStripScrubCoordinator.instance.enqueueShot(
        encodeShotDataUrl: () async => encodedDataUrl,
        enableScrub: scrubEnabled,
      );
      setState(() {
        _stripShots.add(photo);
        _stripScrubFutures.add(scrubFuture);
        _multiShotTotal = total;
        _syncFlashbackSubtitle();
      });
      AppLogger.debug(
        'Classic 4-shot accept: strip=${_stripShots.length}/$total '
        'photo=${photo.id}',
      );
      if (_stripShots.length == 1 && total > 1) {
        final enableSurprise = context
                .read<AppSettingsManager>()
                .settings
                ?.enableSurpriseMeAi ==
            true;
        unawaited(
          maybeKickoffSurpriseMeAfterShot1(
            encodeShotDataUrl: () async => encodedDataUrl,
            enableSurpriseMeAi: enableSurprise,
          ),
        );
      }
      if (_stripShots.length >= total) {
        await _finishFlashbackStrip(theme);
        return;
      }
      await _resumeAfterClassicShotAccepted();
    } finally {
      _flashbackAcceptingShot = false;
      if (mounted) _maybeAdvanceFlashbackAutoChain();
    }
  }

  /// Live preview for the next Classic pose (still already cleared from VM).
  Future<void> _resumeAfterClassicShotAccepted() async {
    if (!mounted) return;
    if (_uvcDevice != null) {
      await _restoreUvcLiveFeedAfterRetake();
      return;
    }
    final ctrl = _captureViewModel.cameraController;
    final healthy = !kIsWeb &&
        ctrl != null &&
        ctrl.value.isInitialized &&
        !ctrl.value.hasError;
    await _captureViewModel.resumeLivePreviewAfterRetake(
      forceReinit: !healthy,
    );
  }

  Future<void> _finishFlashbackStrip(ThemeModel theme) async {
    if (_stripFinishing) return;
    setState(() => _stripFinishing = true);
    _navigatingAwayFromCapture = true;
    _stopPoseIdleTimer();
    try {
      if (widget.sessionKind.isClassicOneShot) {
        await _navigateClassicSingleShotToLooks(theme);
        return;
      }

      // Navigate as soon as encodes are ready — do not block on Gemini scrub
      // (often 20–40s/shot). In-flight scrubs continue; look screen adopts them.
      final dataUrls = <String>[];
      var allScrubbed = _stripShots.isNotEmpty;
      final scrubResults = await _awaitClassicStripEncodeResults();
      for (var i = 0; i < _stripShots.length; i++) {
        final result = i < scrubResults.length ? scrubResults[i] : null;
        if (result != null && result.dataUrl.trim().isNotEmpty) {
          dataUrls.add(result.dataUrl);
          if (!result.scrubbed) allScrubbed = false;
        } else {
          dataUrls.add(
            await ImageHelper.encodeImageToBase64(_stripShots[i].imageFile),
          );
          allScrubbed = false;
        }
      }
      if (!mounted) {
        _clearStripFinishingFlags();
        return;
      }

      final shotOk = dataUrls.length == kStripShotCount;
      if (!shotOk || dataUrls.any((u) => u.trim().isEmpty)) {
        _clearStripFinishingFlags(notify: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(AppStrings.flashbackFinishEncodeFailed)),
          );
        }
        return;
      }
      unawaited(_releaseCaptureHardware());
      ClassicCaptureIntent.clear();
      final shotCleaned = List<bool>.generate(
        dataUrls.length,
        (i) => i < scrubResults.length && scrubResults[i].scrubbed,
      );
      await Navigator.of(context).pushReplacementNamed(
        AppConstants.kRouteFlashbackFilter,
        arguments: FlashbackFilterArgs(
          theme: theme,
          imageDataUrls: dataUrls,
          overlayCleanupAlreadyDone: allScrubbed,
          shotCleaned: shotCleaned,
          classicShotMode: ClassicShotMode.fourShot,
        ),
      );
    } catch (e, st) {
      AppLogger.error(
        'FotoFlashback strip finish failed',
        error: e,
        stackTrace: st,
      );
      _clearStripFinishingFlags(notify: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.flashbackFinishEncodeFailed)),
        );
      }
    }
  }

  /// Classic 1-shot: reuse in-flight encode and open looks — never await Gemini.
  Future<void> _navigateClassicSingleShotToLooks(ThemeModel theme) async {
    if (_stripShots.isEmpty) {
      _clearStripFinishingFlags(notify: true);
      throw StateError('Classic 1-shot finish with no accepted still');
    }
    const encodeTimeout = Duration(seconds: 20);
    final dataUrl = await _classicSingleShotEncodedDataUrl().timeout(
      encodeTimeout,
      onTimeout: () => throw TimeoutException('Classic 1-shot encode timed out'),
    );
    if (dataUrl.trim().isEmpty) {
      _clearStripFinishingFlags(notify: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.flashbackFinishEncodeFailed)),
        );
      }
      return;
    }
    if (!mounted) {
      _clearStripFinishingFlags();
      return;
    }

    final enableSurprise = context
            .read<AppSettingsManager>()
            .settings
            ?.enableSurpriseMeAi ==
        true;
    unawaited(
      maybeKickoffSurpriseMeAfterShot1(
        encodeShotDataUrl: () async => dataUrl,
        enableSurpriseMeAi: enableSurprise,
      ),
    );

    // Look screen adopts in-flight Gemini polish; do not claim scrub done here.
    unawaited(_releaseCaptureHardware());
    ClassicCaptureIntent.clear();
    final filterArgs = FlashbackFilterArgs(
      theme: theme,
      imageDataUrls: [dataUrl],
      overlayCleanupAlreadyDone: false,
      shotCleaned: const [false],
      classicShotMode: ClassicShotMode.single6x4,
    );
    // Direct page route (same Android TV fix as Classic POSE entry) — named
    // `routes:` → const FotoFlashbackFilterScreen() drops typed args.
    await pushReplacementKioskFade<void, void>(
      context,
      FotoFlashbackFilterScreen(filterArgs: filterArgs),
      settings: RouteSettings(
        name: AppConstants.kRouteFlashbackFilter,
        arguments: filterArgs,
      ),
    );
  }

  /// Prefer the encode already started on accept; fall back to a fresh encode.
  Future<String> _classicSingleShotEncodedDataUrl() async {
    final coord = ClassicStripScrubCoordinator.instance;
    if (coord.shotCount >= 1) {
      final results = await coord.awaitEncodedReady();
      if (results.isNotEmpty && results.first.dataUrl.trim().isNotEmpty) {
        return results.first.dataUrl;
      }
    }
    if (_stripScrubFutures.isNotEmpty && _stripScrubFutures.first != null) {
      final result = await _stripScrubFutures.first!;
      if (result.dataUrl.trim().isNotEmpty) return result.dataUrl;
    }
    return ImageHelper.encodeImageToBase64(_stripShots.first.imageFile);
  }

  void _clearStripFinishingFlags({bool notify = false}) {
    _stripFinishing = false;
    _navigatingAwayFromCapture = false;
    if (notify && mounted) setState(() {});
  }

  /// Encode accepted Classic stills for look-picker navigation (4-shot).
  Future<List<ClassicShotScrubResult>> _awaitClassicStripEncodeResults() async {
    const encodeTimeout = Duration(seconds: 20);
    final coord = ClassicStripScrubCoordinator.instance;
    if (coord.shotCount == _stripShots.length && _stripShots.isNotEmpty) {
      return coord.awaitEncodedReady().timeout(
        encodeTimeout,
        onTimeout: () => throw TimeoutException(
          'Classic encode timed out after ${encodeTimeout.inSeconds}s',
        ),
      );
    }

    final out = <ClassicShotScrubResult>[];
    for (var i = 0; i < _stripShots.length; i++) {
      out.add(
        ClassicShotScrubResult(
          dataUrl: await ImageHelper.encodeImageToBase64(
            _stripShots[i].imageFile,
          ).timeout(encodeTimeout),
          scrubbed: false,
        ),
      );
    }
    return out;
  }

  Future<T> _withUvcLock<T>(
    Future<T> Function() fn, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final gate = Completer<void>();
    final previous = _uvcOp;
    _uvcOp = gate.future;
    try {
      await previous.timeout(
        const Duration(seconds: 4),
        onTimeout: () {
          AppLogger.debug('UVC lock queue wait timed out; proceeding');
        },
      );
      return await fn().timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'UVC operation timed out after ${timeout.inSeconds}s',
        ),
      );
    } finally {
      gate.complete();
    }
  }

  void _safeUnawaited(Future<void> future, {required String label}) {
    unawaited(
      future.catchError((Object e, StackTrace st) {
        AppLogger.error(label, error: e, stackTrace: st);
        if (!mounted) return;
        if (isHandledCameraPipelineError(e)) {
          setState(() {
            _uvcPhase = UvcFeedPhase.error;
            _uvcError ??= cameraLoadFailureMessage(e);
            _uvcInitializing = false;
            _uvcOpeningController = false;
          });
        }
      }),
    );
  }

  void _armUvcShutterGrace() {
    _uvcShutterGraceUntil = DateTime.now().add(UvcCaptureConfig.shutterGracePeriod);
  }

  bool get _isWithinUvcShutterGrace => isWithinUvcShutterGrace(
        graceUntil: _uvcShutterGraceUntil,
      );

  void _extendUvcDisconnectIgnore(Duration extension) {
    _uvcIgnoreDisconnectUntil = uvcLaterDisconnectIgnoreUntil(
      current: _uvcIgnoreDisconnectUntil,
      extension: extension,
    );
  }

  bool get _shouldIgnoreUvcDisconnectEvent => uvcShouldIgnoreDisconnectEvent(
        ignoreDisconnectUntil: _uvcIgnoreDisconnectUntil,
        initializing: _uvcInitializing,
        openingController: _uvcOpeningController,
        reconnectInFlight: _uvcReconnectInFlight,
        withinShutterGrace: _isWithinUvcShutterGrace,
        holdLiveFeedClosed: _uvcHoldLiveFeedClosed,
        phase: _uvcPhase,
      );

  void _resetUvcAutoReconnectAttempts() {
    _uvcAutoReconnectAttempts = 0;
    _uvcIgnoreDisconnectUntil = null;
  }

  void _markUvcReconnectExhausted() {
    _uvcReconnectTimer?.cancel();
    _uvcReconnectTimer = null;
    if (!mounted) return;
    setState(() {
      _uvcPhase = UvcFeedPhase.error;
      _uvcError = AppStrings.uvcReconnectFailedMessage;
      _uvcInitializing = false;
      _uvcOpeningController = false;
    });
  }

  bool get _uvcHoldLiveFeedClosed =>
      uvcFeedPhaseBlocksLivePreview(_uvcPhase) ||
      _uvcCaptureInFlight ||
      _captureViewModel.isCapturing ||
      _captureViewModel.capturedPhoto != null ||
      _captureViewModel.isSelectingFromGallery;

  bool get _uvcMayAutoOpenLiveFeed => uvcMayAutoOpenLiveFeed(
        phase: _uvcPhase,
        captureInFlight: _uvcCaptureInFlight,
        hasCapturedPhoto: _captureViewModel.capturedPhoto != null,
        feedAsleep: _uvcFeedAsleep,
      );

  bool get _uvcBlocksConcurrentAutoOpen => uvcBlocksConcurrentAutoOpen(
        initializing: _uvcInitializing,
        openingController: _uvcOpeningController,
        phase: _uvcPhase,
      );

  bool get _uvcReadyForCapture =>
      !_uvcBlocksConcurrentAutoOpen &&
      _uvcController?.value.isInitialized == true;

  void _armUvcPreviewWarmup() {
    _uvcPreviewWarmupPeriod = _canonLvHolding
        ? UvcCaptureConfig.previewWarmupPeriodWhenLvHeld
        : UvcCaptureConfig.previewWarmupPeriod;
    _uvcPreviewReadyAt = DateTime.now();
    _uvcWarmupTimer?.cancel();
    _uvcWarmupTimer = Timer(_uvcPreviewWarmupPeriod, () {
      if (!mounted) return;
      setState(() {});
      _resetUvcIdleSleepTimer();
      // 4-shot only — 1-shot must not auto-fire after USB webcam reopen.
      if (widget.sessionKind.isClassicFourShot) {
        _maybeAdvanceFlashbackAutoChain();
      }
    });
  }

  bool _shouldIgnorePreviewInterrupt(UvcCameraError error) {
    return shouldIgnoreUvcPreviewInterrupt(
      holdLiveFeedClosed: _uvcHoldLiveFeedClosed,
      previewWarmupActive: _uvcPreviewWarmupActive,
      reason: error.reason,
      phaseIsLive: _uvcPhase == UvcFeedPhase.live,
    );
  }

  bool get _uvcPreviewWarmupActive {
    final readyAt = _uvcPreviewReadyAt;
    if (readyAt == null) return false;
    return DateTime.now().difference(readyAt) < _uvcPreviewWarmupPeriod;
  }

  Future<bool> _armCanonLiveViewForPose() async {
    final result = await ensureCanonLiveViewForHdmiPose(
      _captureViewModel.localCameraService,
    );
    _canonLvHolding = result.holding;
    final settle = result.holding
        ? UvcCaptureConfig.canonLvHdmiSettleDelayWhenHeld
        : UvcCaptureConfig.canonLvHdmiSettleDelay;
    await Future<void>.delayed(settle);
    return result.ok;
  }

  void _clearUvcTransientCaptureUi() {
    _showCaptureFlash = false;
    _uvcCaptureInFlight = false;
    _uvcHdmiStillMaskArmed = false;
    _syncCaptureWatchdog(_captureViewModel);
  }

  Future<void> _pulseCaptureFlash({bool playSound = true}) async {
    if (!mounted) return;
    if (playSound) {
      unawaited(_captureViewModel.playCaptureShutterSound());
    }
    setState(() => _showCaptureFlash = true);
    await Future<void>.delayed(UvcCaptureConfig.captureFlashDuration);
    if (!mounted) return;
    setState(() => _showCaptureFlash = false);
  }

  void _resetUvcLiveFeedSessionFlags() {
    _uvcReconnectTimer?.cancel();
    _uvcReconnectTimer = null;
    _uvcWarmupTimer?.cancel();
    _uvcWarmupTimer = null;
    _cancelUvcSessionRecycleTimer();
    _cancelUvcIdleSleepTimer();
    _uvcFeedAsleep = false;
    _uvcLifecyclePaused = false;
    _uvcShutterGraceUntil = null;
    _uvcPreviewReadyAt = null;
    _lastUvcShutterAt = null;
    _uvcLastUiCaptureEndedAt = null;
    _uvcPhase = UvcFeedPhase.live;
    _clearUvcTransientCaptureUi();
    _uvcOpeningController = false;
    _uvcInitializing = false;
  }

  void _cancelUvcSessionRecycleTimer() {
    _uvcSessionRecycleTimer?.cancel();
    _uvcSessionRecycleTimer = null;
  }

  void _cancelUvcIdleSleepTimer() {
    _uvcIdleSleepTimer?.cancel();
    _uvcIdleSleepTimer = null;
  }

  bool get _uvcIdleSleepMayCloseFeed => uvcIdleSleepMayCloseFeed(
        idleSleepEnabled: UvcCaptureConfig.idleSleepEnabled,
        isUsingUvc: _isUsingUvc,
        phase: _uvcPhase,
        captureInFlight: _uvcCaptureInFlight,
        isCapturing: _captureViewModel.isCapturing,
        hasCapturedPhoto: _captureViewModel.capturedPhoto != null,
        withinShutterGrace: _isWithinUvcShutterGrace,
        feedAsleep: _uvcFeedAsleep,
      );

  void _resetUvcIdleSleepTimer() {
    _cancelUvcIdleSleepTimer();
    if (!_uvcIdleSleepMayCloseFeed) return;
    _uvcIdleSleepTimer = Timer(UvcCaptureConfig.idleSleepPeriod, () {
      unawaited(_onUvcIdleSleepTick());
    });
  }

  Future<void> _onUvcIdleSleepTick() async {
    _uvcIdleSleepTimer = null;
    if (!mounted || !_uvcIdleSleepMayCloseFeed) return;
    AppLogger.debug('UVC idle sleep — closing live feed');
    _uvcFeedAsleep = true;
    _cancelUvcSessionRecycleTimer();
    await _closeUvcController();
    if (mounted) setState(() {});
  }

  Future<void> _wakeUvcFromIdleSleep() async {
    if (!_uvcFeedAsleep) return;
    _uvcFeedAsleep = false;
    if (!mounted) return;
    setState(() {});
    await _resumeUvcLiveFeed(reason: 'idleWake');
  }

  void _armUvcSessionRecycleTimer() {
    if (!UvcCaptureConfig.enableSessionRecycleFor(_captureViewModel.deviceType)) {
      return;
    }
    _cancelUvcSessionRecycleTimer();
    _uvcSessionRecycleTimer = Timer(
      UvcCaptureConfig.sessionRecyclePeriod,
      _onUvcSessionRecycleTick,
    );
  }

  void _onUvcSessionRecycleTick() {
    _uvcSessionRecycleTimer = null;
    if (!mounted) return;
    if (!uvcSessionRecycleMayRun(
      sessionRecycleEnabled: UvcCaptureConfig.enableSessionRecycleFor(
        _captureViewModel.deviceType,
      ),
      isUsingUvc: _isUsingUvc,
      mayAutoOpenLiveFeed: _uvcMayAutoOpenLiveFeed,
      blocksConcurrentAutoOpen: _uvcBlocksConcurrentAutoOpen,
      captureInFlight: _uvcCaptureInFlight,
      isCapturing: _captureViewModel.isCapturing,
      withinShutterGrace: _isWithinUvcShutterGrace,
    )) {
      _uvcSessionRecycleTimer = Timer(
        UvcCaptureConfig.sessionRecycleRetryDelay,
        _onUvcSessionRecycleTick,
      );
      return;
    }
    AppLogger.debug('UVC periodic session recycle');
    _safeUnawaited(
      _resumeUvcLiveFeed(reason: 'sessionRecycle'),
      label: 'UVC session recycle failed',
    );
  }

  Future<XFile> _takeUvcPicture(
    UvcCameraController ctrl, {
    required String source,
  }) async {
    final attempts = uvcTakePictureAttemptsForSource(source);
    final timeout = source == 'preview_interrupt'
        ? UvcCaptureConfig.interruptTakePictureTimeout
        : UvcCaptureConfig.takePictureTimeout;
    const retryDelay = UvcCaptureConfig.interruptTakePictureRetryDelay;

    Object? lastError;
    for (var attempt = 0; attempt < attempts; attempt++) {
      final active = _uvcController;
      if (active == null || !active.value.isInitialized) {
        break;
      }
      try {
        return await active.takePicture().timeout(
          timeout,
          onTimeout: () => throw TimeoutException(
            'UVC takePicture timed out after ${timeout.inSeconds}s '
            '(source=$source attempt=${attempt + 1}/$attempts)',
          ),
        );
      } catch (e) {
        lastError = e;
        if (attempt < attempts - 1) {
          await Future<void>.delayed(retryDelay);
        }
      }
    }
    throw lastError ?? Exception('UVC takePicture failed (source=$source)');
  }

  Future<XFile> _obtainUvcStillFile(
    UvcCameraController ctrl, {
    required String source,
  }) async {
    // UVC preview is a GPU Texture — raster rarely works; plugin takePicture
    // grabs the next UVC frame (works for DSLR HDMI pause when a frame arrives).
    try {
      return await _takeUvcPicture(ctrl, source: source);
    } catch (pluginError) {
      if (!uvcAllowsRasterFallback(source)) {
        AppLogger.error(
          'UVC takePicture failed (no raster fallback)',
          error: pluginError,
        );
        rethrow;
      }
      AppLogger.error(
        'UVC takePicture failed; trying raster fallback',
        error: pluginError,
      );
      final raster = await rasterCaptureRepaintBoundary(
        boundaryKey: _uvcPreviewBoundaryKey,
        maxLongEdge: UvcCaptureConfig.effectiveNormalizeMaxDimension,
      );
      if (raster != null) {
        AppLogger.debug('UVC still from raster fallback (source=$source)');
        return raster;
      }
      rethrow;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _captureViewModel = CaptureViewModel(
      appSettingsManager: context.read<AppSettingsManager>(),
    );
    // Mode is widget.sessionKind only — never restore Classic prefs for FotoZen.
    final ctorArgs = widget.captureArgs;
    if (widget.sessionKind.isClassic) {
      _prefillApplied = true;
      _applyClassicCaptureArgs(ctorArgs);
    } else {
      ClassicCaptureIntent.clear();
    }
    _captureViewModel.addListener(_onCaptureViewModelStateChanged);
    ClassicStripScrubCoordinator.instance.addListener(_onScrubProgressChanged);
    _tryAdoptTermsPrewarmOnInitIfAllowed();
    _skipUvcForCameraXSession =
        _captureViewModel.preferEnumeratedCameraPath ||
        CaptureViewModel.hasEnumerationCache;
    _attachUvcDeviceEvents();

    _hardwareKeySub?.cancel();
    _hardwareKeySub = HardwareKeyService.events.listen((e) async {
      if (!e.isActionDown) return;
      _notePoseUserActivity();
      if (_captureViewModel.capturedPhoto != null) return;
      if (_captureViewModel.isCountingDown ||
          _captureViewModel.isCapturing ||
          _uvcCaptureInFlight ||
          _flashbackCountdownStarting) {
        return;
      }
      if (!UvcHardwareKeyCodes.isShutterKey(e.keyCode)) return;
      if (_isFlashbackSingleShot) {
        if (!classicOneShotMayAcceptExternalShutter(_oneShotPhase)) return;
        _lastUvcShutterAt = DateTime.now();
        _armUvcShutterGrace();
        _oneShotRequestGuestCapture();
        return;
      }
      if (_isFlashbackMultiShot) {
        if (_captureViewModel.capturedPhoto != null ||
            _stripShots.length >= (_multiShotTotal ?? 0)) {
          return;
        }
        unawaited(_startFlashbackAutoCountdown());
        return;
      }
      // FotoZen: TV remote DPAD/ENTER often also activates the Capture button —
      // ignore keys once a capture session has started.
      if (_fotoZenCaptureLocked) return;
      if (_captureViewModel.capturedPhoto != null) return;
      if (_isUsingUvc && _uvcController?.value.isInitialized == true) {
        _triggerUvcCapture(
          source: 'android_key_${e.keyCode}',
          externalSignal: true,
        );
        return;
      }
      if (e.keyCode == UvcHardwareKeyCodes.volumeUp ||
          e.keyCode == UvcHardwareKeyCodes.volumeDown) {
        _fotoZenCaptureLocked = true;
        await _captureViewModel.capturePhotoWithCountdown();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final deviceType = _captureViewModel.deviceType ??
          CaptureViewModel.prewarmedDeviceType;
      if (_captureViewModel.isReady &&
          !kioskShouldTryUvcBeforeCameraX(deviceType)) {
        unawaited(_finishPrewarmPoseSetup());
        return;
      }
      _schedulePoseSetupAfterTransition();
    });
  }

  void _tryAdoptTermsPrewarmOnInitIfAllowed() {
    if (!CaptureViewModel.hasPrewarmedCamera) return;
    final prewarmedType = CaptureViewModel.prewarmedDeviceType;
    if (!shouldAdoptTermsPrewarmOnPoseInit(prewarmedType)) return;
    if (prewarmedType != null) {
      _captureViewModel.setDeviceType(prewarmedType);
    }
    _captureViewModel.adoptPrewarmIfAvailable();
  }

  Future<void> _finishPrewarmPoseSetup() async {
    if (!mounted) return;
    unawaited(
      HardwareKeyService.setEnabled(true).then((_) {
        if (mounted) _hardwareKeysEnabled = true;
      }),
    );
    unawaited(_captureViewModel.loadPreviewRotation());
    _syncPoseIdleTimer(_captureViewModel);
    if (widget.sessionKind.isClassicFourShot) {
      _maybeAdvanceFlashbackAutoChain();
    } else if (widget.sessionKind.isClassicOneShot) {
      _oneShotOnViewModelTick();
    }
  }

  void _cancelPoseLoadingWatchdog() {
    _poseLoadingWatchdog?.cancel();
    _poseLoadingWatchdog = null;
  }

  void _armPoseLoadingWatchdog() {
    _cancelPoseLoadingWatchdog();
    _poseLoadingWatchdog = Timer(const Duration(seconds: 28), () {
      if (!mounted) return;
      if (!_isCapturePreviewStarting(_captureViewModel)) return;
      AppLogger.error('POSE preview loading exceeded watchdog');
      _forceClearPoseLoadingState();
    });
  }

  void _forceClearPoseLoadingState() {
    _captureViewModel.clearStuckLoadingFlags();
    if (_uvcDevice != null && !_uvcFeedIsHealthy) {
      unawaited(_clearUvcBinding());
    }
    if (!mounted) return;
    setState(() {
      _uvcInitializing = false;
      _uvcOpeningController = false;
      _uvcError ??= 'Camera took too long to start. Tap Retry or use Gallery.';
    });
  }

  /// Defers camera work until the route transition finishes (smoother POSE entry).
  void _schedulePoseSetupAfterTransition() {
    if (!mounted) return;

    var setupStarted = false;
    Timer? setupFallback;

    void beginSetupOnce() {
      if (setupStarted || !mounted) return;
      setupStarted = true;
      setupFallback?.cancel();
      unawaited(_beginPoseCaptureSetup());
    }

    if (_isFlashbackFourShot && _stripShots.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => beginSetupOnce());
      return;
    }

    if (CaptureViewModel.hasPrewarmedCamera) {
      WidgetsBinding.instance.addPostFrameCallback((_) => beginSetupOnce());
      return;
    }

    // Android TV launchers: skip waiting on route animation (often never completes).
    if (defaultTargetPlatform == TargetPlatform.android) {
      WidgetsBinding.instance.addPostFrameCallback((_) => beginSetupOnce());
      setupFallback = Timer(const Duration(seconds: 1), beginSetupOnce);
      return;
    }

    final animation = ModalRoute.of(context)?.animation;
    if (animation != null && !animation.isCompleted) {
      void onStatus(AnimationStatus status) {
        if (status == AnimationStatus.completed) {
          animation.removeStatusListener(onStatus);
          beginSetupOnce();
        }
      }
      animation.addStatusListener(onStatus);
      setupFallback = Timer(const Duration(seconds: 3), () {
        animation.removeStatusListener(onStatus);
        beginSetupOnce();
      });
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => beginSetupOnce());
  }

  Future<void> _beginPoseCaptureSetup() async {
    if (!mounted) return;
    _armPoseLoadingWatchdog();
    final deviceType = _captureViewModel.deviceType ??
        CaptureViewModel.prewarmedDeviceType;
    final setupTimeout = kioskShouldTryUvcBeforeCameraX(deviceType)
        ? const Duration(seconds: 45)
        : const Duration(seconds: 30);
    try {
      await _beginPoseCaptureSetupBody().timeout(
        setupTimeout,
        onTimeout: () => throw TimeoutException('POSE camera setup timed out'),
      );
    } catch (e, st) {
      AppLogger.error('POSE camera setup failed', error: e, stackTrace: st);
      _forceClearPoseLoadingState();
    } finally {
      _cancelPoseLoadingWatchdog();
    }
  }

  Future<void> _beginPoseCaptureSetupBody() async {
    if (!mounted) return;
    unawaited(
      HardwareKeyService.setEnabled(true).then((_) {
        if (mounted) _hardwareKeysEnabled = true;
      }),
    );

    if (_captureViewModel.usesSidecarLivePreview) {
      AppLogger.info('POSE using Pi DSLR sidecar live preview');
      await _captureViewModel.prepareSidecarLivePreview();
      if (!mounted) return;
      await _finishPrewarmPoseSetup();
      return;
    }

    // Classic + Pi sidecar: prefer USB MJPEG from the LV keeper. HDMI→capture
    // card stays blank on FZ200D even while movie LV holds (Starting camera…).
    if (widget.sessionKind.isClassic &&
        _captureViewModel.localCameraService?.isConfigured == true) {
      AppLogger.info(
        'POSE Classic: forcing Pi USB live preview (skip HDMI/UVC)',
      );
      _captureViewModel.localCameraService?.setForceLivePreview(true);
      await _armCanonLiveViewForPose();
      if (!mounted) return;
      await _captureViewModel.prepareSidecarLivePreview();
      if (!mounted) return;
      unawaited(
        _captureViewModel.localCameraService?.postClientEvent(
          'pose_sidecar_preview',
          {'forced': true},
        ),
      );
      await _finishPrewarmPoseSetup();
      return;
    }

    var deviceType = _captureViewModel.deviceType ??
        CaptureViewModel.prewarmedDeviceType;
    final kioskLikely = kioskShouldTryUvcBeforeCameraX(deviceType);

    if (!kioskLikely) {
      await CaptureViewModel.awaitPrewarmIfInFlight(
        timeout: const Duration(seconds: 8),
      );
      if (!mounted) return;
    }

    final prewarmedType = CaptureViewModel.prewarmedDeviceType;
    if (prewarmedType != null && _captureViewModel.deviceType == null) {
      _captureViewModel.setDeviceType(prewarmedType);
      deviceType ??= prewarmedType;
    }

    if (deviceType == null) {
      try {
        deviceType = await DeviceClassifier.getDeviceType(context).timeout(
          const Duration(seconds: 3),
        );
        if (mounted) _captureViewModel.setDeviceType(deviceType);
      } catch (_) {
        // Best-effort; setup continues with null device type.
      }
    }

    final kioskUvc = kioskShouldTryUvcBeforeCameraX(deviceType);
    if (kioskUvc) {
      _skipUvcForCameraXSession = false;
      await _releaseCameraXForUvcSession();
      if (!_uvcFeedIsHealthy) {
        if (defaultTargetPlatform == TargetPlatform.android) {
          await UvcSessionCoordinator.waitBeforeOpen(
            deviceType: _captureViewModel.deviceType,
          );
          if (!mounted) return;
        }
        final uvcReady = await _tryInitializeUvcForPoseEntry(
          preferred: _uvcDevice,
          deviceType: deviceType,
        );
        if (!mounted) return;
        if (uvcReady) {
          await _finishPrewarmPoseSetup();
          return;
        }
        await _clearUvcBinding();
        // CameraX fallback below — do not retry UVC in the same POSE visit.
        _skipUvcForCameraXSession = true;
      } else {
        await _finishPrewarmPoseSetup();
        return;
      }
    }

    if (!_captureViewModel.isReady) {
      _tryAdoptTermsPrewarmOnInitIfAllowed();
    }

    if (_captureViewModel.isReady && !kioskUvc) {
      _skipUvcForCameraXSession = true;
      await _finishPrewarmPoseSetup();
      return;
    }

    if (_captureViewModel.preferEnumeratedCameraPath && !kioskUvc) {
      _skipUvcForCameraXSession = true;
    }

    await _captureViewModel.loadPreviewRotation();
    if (!mounted) return;
    await _resetAndInitializeCameras();
    if (!mounted) return;
    await _finishPrewarmPoseSetup();
    if (!mounted) return;
    if (!_uvcFeedIsHealthy &&
        !_captureViewModel.isReady &&
        !_captureViewModel.isLoadingCameras &&
        !_captureViewModel.isInitializing) {
      _forceClearPoseLoadingState();
    }
    _syncPoseIdleTimer(_captureViewModel);
  }

  Future<void> _releaseCameraXForUvcSession() async {
    unawaited(CaptureViewModel.disposePrewarm());
    if (_captureViewModel.isReady || _captureViewModel.isInitializing) {
      await _captureViewModel.disposeCamera();
    }
    _skipUvcForCameraXSession = false;
  }

  /// Common function to reset and initialize cameras
  /// Used both when entering the screen and when tapping the reload button
  Future<void> _resetAndInitializeCameras({bool forceRefresh = false}) async {
    if (!mounted) return;

    final initGate = Completer<void>();
    final previousInit = _captureInitOp;
    _captureInitOp = initGate.future;
    await previousInit.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        AppLogger.debug('POSE init queue wait timed out; proceeding');
      },
    );

    try {
      await _resetAndInitializeCamerasBody(forceRefresh: forceRefresh).timeout(
        const Duration(seconds: 28),
        onTimeout: () => throw TimeoutException('Camera reset timed out'),
      );
    } finally {
      initGate.complete();
    }
  }

  Future<void> _resetAndInitializeCamerasBody({bool forceRefresh = false}) async {
    if (!mounted) return;

    final kioskUvc =
        kioskShouldTryUvcBeforeCameraX(_captureViewModel.deviceType);

    if (!forceRefresh &&
        _captureViewModel.isReady &&
        _captureViewModel.preferEnumeratedCameraPath &&
        !kioskUvc) {
      _skipUvcForCameraXSession = true;
      _syncPoseIdleTimer(_captureViewModel);
      return;
    }

    AppDeviceType? deviceType;
    try {
      deviceType = await DeviceClassifier.getDeviceType(context);
      if (mounted) _captureViewModel.setDeviceType(deviceType);
    } catch (e, st) {
      AppLogger.error(
        'Failed to detect device type',
        error: e,
        stackTrace: st,
      );
      await ErrorReportingManager.recordError(
        e,
        st,
        reason: 'getDeviceType failed',
        fatal: false,
      );
    }

    if (kioskShouldTryUvcBeforeCameraX(deviceType)) {
      _skipUvcForCameraXSession = false;
    } else {
      _skipUvcForCameraXSession = _captureViewModel.preferEnumeratedCameraPath;
    }

    if (_uvcFeedIsHealthy && !_uvcFeedAsleep) {
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.android &&
        !_skipUvcForCameraXSession) {
      await UvcSessionCoordinator.waitBeforeOpen(
        deviceType: _captureViewModel.deviceType,
      );
      if (!mounted) return;

      final uvcAttached = await hasAttachedUvcDevices();
      if (!mounted) return;

      if (uvcAttached) {
        unawaited(CaptureViewModel.disposePrewarm());
        final uvcReady = await _tryInitializeUvcQuick(preferred: _uvcDevice);
        if (!mounted) return;
        if (uvcReady) {
          await _releaseCameraXForUvcSession();
          unawaited(_captureViewModel.warmCameraEnumerationCache());
          _stopUvcEntryProbe();
          _startUvcTvProbeIfNeeded();
          return;
        }
        await _clearUvcBinding();
      }
    }

    await _captureViewModel.resetAndInitializeCameras(
      forceRefresh: forceRefresh,
    );
    if (!mounted) return;

    final uploadAllowed = context.read<AppSettingsManager>().settings
            ?.photoUploadAllowed ==
        true;
    final camerasEmpty = _captureViewModel.availableCameras.isEmpty;
    final skipUvcProbe = !shouldProbeUvcAfterNoCameraX(
      photoUploadAllowed: uploadAllowed,
      camerasEmpty: camerasEmpty,
      uvcFeedHealthy: _uvcFeedIsHealthy,
      cameraReady: _captureViewModel.isReady,
    );

    if (skipUvcProbe) {
      _stopUvcEntryProbe();
      _uvcTvProbeTimer?.cancel();
      _uvcTvProbeTimer = null;
    } else if (!_uvcFeedIsHealthy &&
        !_captureViewModel.isReady &&
        !_captureViewModel.isLoadingCameras &&
        !_captureViewModel.isInitializing &&
        !_skipUvcForCameraXSession &&
        defaultTargetPlatform == TargetPlatform.android) {
      _startUvcEntryProbe();
    } else {
      _stopUvcEntryProbe();
    }
    if (!skipUvcProbe) {
      _startUvcTvProbeIfNeeded();
    }
    await _reportCaptureScreenNoCameraIfNeeded();
  }

  /// One quick UVC attempt with timeout so CameraX fallback is not blocked long.
  Future<bool> _tryInitializeUvcQuick({UvcCameraDevice? preferred}) async {
    return _tryInitializeUvcForPoseEntry(
      preferred: preferred,
      deviceType: _captureViewModel.deviceType,
    );
  }

  /// Opens UVC on POSE entry; kiosks use a longer budget than [quickOpenTimeout].
  Future<bool> _tryInitializeUvcForPoseEntry({
    UvcCameraDevice? preferred,
    AppDeviceType? deviceType,
  }) async {
    if (!mounted) return false;
    final timeout = uvcPoseEntryOpenTimeout(deviceType);
    try {
      return await _tryInitializeUvc(preferred: preferred).timeout(
        timeout,
        onTimeout: () => throw TimeoutException('UVC open timed out'),
      );
    } on TimeoutException {
      await _awaitUvcLockIdle();
      await _clearUvcBinding();
      return false;
    } catch (_) {
      await _awaitUvcLockIdle();
      await _clearUvcBinding();
      return false;
    }
  }

  Future<void> _awaitUvcLockIdle({
    Duration cap = const Duration(seconds: 6),
  }) async {
    try {
      await _uvcOp.timeout(cap);
    } on TimeoutException {
      AppLogger.debug('UVC lock still held after ${cap.inSeconds}s');
    }
  }

  void _startUvcEntryProbe() {
    _uvcEntryProbeTimer?.cancel();
    unawaited(_probeUvcForEntry());
    _uvcEntryProbeTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted ||
          _uvcFeedIsHealthy ||
          _captureViewModel.capturedPhoto != null) {
        _stopUvcEntryProbe();
        return;
      }
      if (_captureViewModel.isReady && !_isUsingUvc) {
        _stopUvcEntryProbe();
        return;
      }
      if (_skipUvcForCameraXSession ||
          _captureViewModel.isLoadingCameras ||
          _captureViewModel.isInitializing) {
        return;
      }
      if (_uvcReconnectInFlight || _uvcBlocksConcurrentAutoOpen) return;
      _safeUnawaited(
        _probeUvcForEntry(),
        label: 'UVC entry probe failed',
      );
    });
  }

  void _stopUvcEntryProbe() {
    _uvcEntryProbeTimer?.cancel();
    _uvcEntryProbeTimer = null;
  }

  Future<void> _probeUvcForEntry() async {
    if (!mounted || _uvcFeedIsHealthy || _skipUvcForCameraXSession) return;
    if (_captureViewModel.isLoadingCameras ||
        _captureViewModel.isInitializing) {
      return;
    }
    await _captureInitOp.catchError((_) {});
    if (!mounted || _uvcFeedIsHealthy) return;
    final ok = await _tryInitializeUvc();
    if (!mounted || !ok) return;
    _stopUvcEntryProbe();
    setState(() {});
  }

  bool get _uvcFeedIsHealthy =>
      _uvcDevice != null && _uvcController?.value.isInitialized == true;

  Future<bool> _tryInitializeUvc({UvcCameraDevice? preferred}) async {
    if (!mounted || _captureViewModel.capturedPhoto != null) return false;
    final device = preferred ??
        await probeFirstUvcDevice();
    if (device == null) return false;
    return _ensureUvcDeviceBound(device);
  }

  Future<void> _clearUvcBinding() async {
    _uvcTvProbeTimer?.cancel();
    _uvcTvProbeTimer = null;
    _stopUvcEntryProbe();
    _uvcReconnectTimer?.cancel();
    _resetUvcAutoReconnectAttempts();
    _uvcReconnectInFlight = false;
    await _closeUvcController();
    if (!mounted) return;
    setState(() {
      _uvcDevice = null;
      _uvcError = null;
      _uvcInitializing = false;
      _uvcOpeningController = false;
      _uvcPhase = UvcFeedPhase.live;
    });
  }

  void _startUvcTvProbeIfNeeded() {
    if (_captureViewModel.deviceType != AppDeviceType.androidTv) return;
    if (_uvcFeedIsHealthy) {
      _uvcTvProbeTimer?.cancel();
      _uvcTvProbeTimer = null;
      return;
    }
    if (_captureViewModel.isReady && !_isUsingUvc) {
      _uvcTvProbeTimer?.cancel();
      _uvcTvProbeTimer = null;
      return;
    }
    _uvcTvProbeTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      if (_uvcFeedIsHealthy || _captureViewModel.capturedPhoto != null) {
        _uvcTvProbeTimer?.cancel();
        _uvcTvProbeTimer = null;
        return;
      }
      if (_uvcReconnectInFlight || _uvcBlocksConcurrentAutoOpen) return;
      if (_captureViewModel.isReady && !_isUsingUvc) return;
      _safeUnawaited(
        _tryInitializeUvc(),
        label: 'UVC TV periodic probe failed',
      );
    });
  }

  Future<void> _tryBindUvcFromHotplug(UvcCameraDevice eventDevice) async {
    if (_skipUvcForCameraXSession) return;
    await _captureInitOp.catchError((_) {});
    if (!mounted ||
        _uvcDevice != null ||
        _captureViewModel.capturedPhoto != null) {
      return;
    }
    if (_uvcReconnectInFlight || _uvcBlocksConcurrentAutoOpen) return;

    final device = await resolveUvcDeviceForHotplug(
      eventDevice,
    );
    if (!mounted || device == null) return;

    final ok = await _ensureUvcDeviceBound(device);
    if (!mounted) return;
    if (ok) {
      _stopUvcEntryProbe();
      _uvcTvProbeTimer?.cancel();
      _uvcTvProbeTimer = null;
      return;
    }
    await _clearUvcBinding();
    if (!mounted) return;
    await _captureViewModel.resetAndInitializeCameras();
    if (mounted) _startUvcTvProbeIfNeeded();
  }

  Future<void> _reportCaptureScreenNoCameraIfNeeded() async {
    if (!mounted || _isUsingUvc) return;
    final vm = _captureViewModel;
    if (vm.isLoadingCameras || vm.isInitializing) return;
    if (vm.availableCameras.isNotEmpty) return;
    if (vm.hasError) return;

    await vm.reportCameraNotFound(
      reason: 'No camera available on capture screen',
      extraInfo: const {'source': 'capture_screen_idle'},
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _captureViewModel.removeListener(_onCaptureViewModelStateChanged);
    ClassicStripScrubCoordinator.instance.removeListener(_onScrubProgressChanged);
    _stopPoseIdleTimer();
    _cancelPoseLoadingWatchdog();
    _cancelCaptureWatchdog();
    _cancelFlashbackAutoTimers();
    _uvcReconnectTimer?.cancel();
    _uvcReconnectTimer = null;
    _uvcTvProbeTimer?.cancel();
    _uvcTvProbeTimer = null;
    _stopUvcEntryProbe();
    _uvcWarmupTimer?.cancel();
    _uvcWarmupTimer = null;
    _cancelUvcSessionRecycleTimer();
    _cancelUvcIdleSleepTimer();
    _uvcDeviceEventsSub?.cancel();
    _uvcDeviceEventsSub = null;
    _hardwareKeySub?.cancel();
    _hardwareKeySub = null;
    if (_hardwareKeysEnabled) {
      HardwareKeyService.setEnabled(false);
    }
    if (_uvcShutterKeysEnabled) {
      HardwareKeyService.setUvcShutterKeysEnabled(false);
    }
    unawaited(
      _disposeUvc().catchError((Object e, StackTrace st) {
        AppLogger.error('UVC dispose failed on screen dispose', error: e, stackTrace: st);
      }),
    );
    _captureViewModel.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final inForeground = state == AppLifecycleState.resumed;
    if (_appInForeground != inForeground) {
      _appInForeground = inForeground;
      if (inForeground) {
        _syncPoseIdleTimer(_captureViewModel);
      } else {
        _stopPoseIdleTimer();
      }
    }

    if (!_isUsingUvc) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      if (uvcLifecycleShouldPauseFeed(
        lifecyclePauseEnabled: UvcCaptureConfig.lifecyclePauseEnabled,
        isUsingUvc: _isUsingUvc,
        holdLiveFeedClosed: _uvcHoldLiveFeedClosed,
        hasOpenController: _uvcController != null,
      )) {
        _uvcLifecyclePaused = true;
        _cancelUvcIdleSleepTimer();
        unawaited(_closeUvcController());
      }
      return;
    }

    if (state == AppLifecycleState.resumed &&
        uvcLifecycleShouldResumeFeed(
          lifecyclePauseEnabled: UvcCaptureConfig.lifecyclePauseEnabled,
          isUsingUvc: _isUsingUvc,
          lifecyclePaused: _uvcLifecyclePaused,
          mayAutoOpenLiveFeed: _uvcMayAutoOpenLiveFeed,
          blocksConcurrentAutoOpen: _uvcBlocksConcurrentAutoOpen,
          withinShutterGrace: _isWithinUvcShutterGrace,
          hasOpenController: _uvcController != null,
        )) {
      _uvcLifecyclePaused = false;
      _scheduleUvcReconnect('appResumed');
    }
  }

  @override
  void didChangeMetrics() {
    // On some Android tablets, orientation changes don't reliably update camera preview
    // unless we refresh rotation metadata. Keep this lightweight.
    _captureViewModel.refreshDisplayRotation();
  }

  Future<void> _closeUvcController() async {
    await _withUvcLock(_closeUvcControllerUnlocked);
  }

  VoidCallback? _uvcControllerListener;

  void _attachUvcControllerListener(UvcCameraController ctrl) {
    _detachUvcControllerListener();
    void listener() {
      if (!mounted) return;
      if (ctrl.value.isInitialized) {
        setState(() {});
      }
    }
    _uvcControllerListener = listener;
    ctrl.addListener(listener);
  }

  void _detachUvcControllerListener() {
    final listener = _uvcControllerListener;
    final ctrl = _uvcController;
    if (listener != null && ctrl != null) {
      ctrl.removeListener(listener);
    }
    _uvcControllerListener = null;
  }

  Future<void> _closeUvcControllerUnlocked() async {
    _extendUvcDisconnectIgnore(UvcCaptureConfig.reconnectIgnoreDisconnectPeriod);
    _detachUvcHardwareListeners();
    _detachUvcControllerListener();
    await _setUvcShutterKeysEnabled(false);
    _uvcPreviewReadyAt = null;
    final ctrl = _uvcController;
    _uvcController = null;
    if (ctrl != null) {
      final teardown = ctrl.dispose();
      UvcSessionCoordinator.trackTeardown(teardown);
      try {
        await teardown;
      } catch (_) {
        // Best-effort.
      }
    }
  }

  Future<void> _handleSelectFromGallery(CaptureViewModel viewModel) async {
    await pauseCapturePreviewForGallery(
      isUsingUvc: _isUsingUvc,
      closeUvc: _closeUvcController,
      disposeBuiltInCamera: _captureViewModel.disposeCamera,
      setUvcPhase: (phase) => _uvcPhase = phase,
      cancelUvcSessionRecycle: _cancelUvcSessionRecycleTimer,
    );
    if (!mounted) return;
    setState(() {});

    try {
      await viewModel.selectFromGallery();
    } finally {
      if (mounted) {
        final accepted = viewModel.capturedPhoto != null;
        await finalizeGallerySelection(
          isUsingUvc: _isUsingUvc,
          photoAccepted: accepted,
          closeUvc: _closeUvcController,
          disposeBuiltInCamera: _captureViewModel.disposeCamera,
          setUvcPhase: (phase) => _uvcPhase = phase,
          cancelUvcReconnect: () => _uvcReconnectTimer?.cancel(),
          bumpPreviewGeneration: () => _uvcPreviewGeneration++,
        );
        if (!accepted) {
          await resumeCapturePreviewAfterGallery(
            isUsingUvc: _isUsingUvc,
            hasCapturedPhoto: viewModel.capturedPhoto != null,
            setUvcPhase: (phase) => _uvcPhase = phase,
            resumeUvcLiveFeed: (reason) => _resumeUvcLiveFeed(reason: reason),
            resumeBuiltInPreview: _captureViewModel.resumeLivePreviewAfterRetake,
          );
        }
        setState(() {});
      }
    }
  }

  CaptureRouteArgs _flashbackRouteArgs() {
    _syncFlashbackSubtitle();
    return CaptureRouteArgs(
      returnPhotoOnly: true,
      subtitleHint: _subtitleHint,
      multiShotTotal: _multiShotTotal,
      flashbackTheme: _flashbackTheme,
      acceptedStripShots: List<PhotoModel>.from(_stripShots),
      classicShotMode: widget.sessionKind.classicShotMode,
    );
  }

  CaptureRouteArgs? get _currentCaptureRouteArgs {
    if (_isClassicPose) return _flashbackRouteArgs();
    if (!_returnPhotoOnly &&
        (_subtitleHint == null || _subtitleHint!.isEmpty)) {
      return null;
    }
    return CaptureRouteArgs(
      returnPhotoOnly: _returnPhotoOnly,
      subtitleHint: _subtitleHint,
    );
  }

  Future<void> _handleRetake(BuildContext context) async {
    _cancelFlashbackAutoTimers();
    _fotoZenCaptureLocked = false;
    // 1-shot session: never open poses 2–4 via the strip remount chain.
    if (widget.sessionKind.isClassicOneShot) {
      if (_stripShots.isNotEmpty ||
          _oneShotPhase == ClassicOneShotPhase.finishing ||
          _oneShotPhase == ClassicOneShotPhase.done) {
        final theme = _flashbackTheme ?? ClassicCaptureIntent.peekTheme();
        if (theme != null) {
          await _finishFlashbackStrip(theme);
        }
        return;
      }
      // Explicit retake of the review still only — user must tap Capture again.
      _oneShotDispatch(ClassicOneShotEvent.guestRetake);
      await handleCapturedPhotoRetake(
        context: context,
        viewModel: _captureViewModel,
        isMounted: () => mounted,
        routeArguments: _currentCaptureRouteArgs,
        skipWebRouteReplace: true,
      );
      if (!mounted) return;
      if (_uvcDevice != null) {
        await _restoreUvcLiveFeedAfterRetake();
      } else {
        await _captureViewModel.resumeLivePreviewAfterRetake();
      }
      return;
    }
    final flashback = _isFlashbackFourShot;
    // Web: remount capture route so getUserMedia restarts (same State leaves a
    // black / dead stream after takePicture). Strip progress is carried in args.
    // Native/UVC: stay on this State and force a controller re-init.
    await handleCapturedPhotoRetake(
      context: context,
      viewModel: _captureViewModel,
      isMounted: () => mounted,
      routeArguments: _currentCaptureRouteArgs,
      skipWebRouteReplace: flashback,
    );
    if (!mounted) return;
    if (_uvcDevice != null) {
      await _restoreUvcLiveFeedAfterRetake();
      if (mounted && flashback) _maybeAdvanceFlashbackAutoChain();
      return;
    }
    if (flashback) {
      // Web getUserMedia dies after takePicture — always remount the stream.
      // Native: only hard-remount when the preview is actually dead.
      final ctrl = _captureViewModel.cameraController;
      final healthy = !kIsWeb &&
          ctrl != null &&
          ctrl.value.isInitialized &&
          !ctrl.value.hasError;
      await _captureViewModel.resumeLivePreviewAfterRetake(
        forceReinit: !healthy,
      );
      if (mounted) _maybeAdvanceFlashbackAutoChain();
      return;
    }
    await _captureViewModel.resumeLivePreviewAfterRetake();
  }

  Future<void> _handleCaptureBack(BuildContext context) async {
    _notePoseUserActivity();
    _cancelFlashbackAutoTimers();
    if (_captureViewModel.capturedPhoto != null) {
      await _handleRetake(context);
      return;
    }
    if (_isFlashbackMultiShot && _stripShots.isNotEmpty) {
      _captureViewModel.cancelCountdown();
      setState(_dropLastStripShot);
      _maybeAdvanceFlashbackAutoChain();
      return;
    }
    await _exitCaptureToTerms(
      sessionEndContext: 'capture_back',
      endCustomerSession: false,
    );
  }

  Future<void> _restoreUvcLiveFeedAfterRetake() async {
    _uvcPhase = UvcFeedPhase.live;
    _uvcShutterGraceUntil = null;
    _lastUvcShutterAt = null;
    _uvcLastUiCaptureEndedAt = null;
    _uvcError = null;
    _clearUvcTransientCaptureUi();

    final ctrl = _uvcController;
    if (UvcCaptureConfig.keepControllerOpenDuringReview &&
        ctrl != null &&
        ctrl.value.isInitialized) {
      AppLogger.debug('UVC retake: reusing open feed');
      _uvcPreviewGeneration++;
      _armUvcPreviewWarmup();
      _attachUvcHardwareListeners(ctrl);
      await _setUvcShutterKeysEnabled(true);
      if (mounted) setState(() {});
      return;
    }
    await _resumeUvcLiveFeed(reason: 'retake');
  }

  /// Full teardown + delay + permission nudge + reopen (retake / reconnect).
  Future<void> _resumeUvcLiveFeed({required String reason}) async {
    AppLogger.debug('UVC resume live feed ($reason)');
    if (!mounted || _uvcDevice == null) {
      return;
    }
    if (_uvcReconnectInFlight) {
      AppLogger.debug('UVC resume skipped — reconnect already in flight');
      return;
    }
    if (reason == 'retryTap') {
      _resetUvcAutoReconnectAttempts();
    }
    if (!uvcMayResumeLiveFeed(
      phase: _uvcPhase,
      hasCapturedPhoto: _captureViewModel.capturedPhoto != null,
    )) {
      return;
    }

    _uvcReconnectInFlight = true;
    _uvcReconnectTimer?.cancel();
    _uvcShutterGraceUntil = null;
    _lastUvcShutterAt = null;
    _clearUvcTransientCaptureUi();
    _uvcPhase = UvcFeedPhase.live;
    _extendUvcDisconnectIgnore(UvcCaptureConfig.reconnectIgnoreDisconnectPeriod);

    // Still capture / idle often exits Canon LV; re-arm before HDMI reopen.
    await _armCanonLiveViewForPose();
    if (!mounted || _uvcDevice == null) {
      _uvcReconnectInFlight = false;
      return;
    }

    setState(() {
      _uvcError = null;
      _uvcInitializing = true;
    });

    try {
      await _withUvcLock(_closeUvcControllerUnlocked);
      if (!UvcCaptureConfig.keepControllerOpenDuringReview) {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      }
      final reopenDelay = UvcCaptureConfig.reopenFeedDelayFor(
        _captureViewModel.deviceType,
      );
      _extendUvcDisconnectIgnore(reopenDelay + const Duration(seconds: 1));
      await Future<void>.delayed(reopenDelay);
      if (!mounted || _uvcDevice == null || !_uvcMayAutoOpenLiveFeed) {
        return;
      }

      final device = _uvcDevice;
      if (device == null) return;
      final permitted = await ensureUvcPermissions(device);
      if (!mounted) return;
      if (!permitted) {
        setState(() {
          _uvcPhase = UvcFeedPhase.error;
          _uvcError = 'USB camera permission was not granted.';
        });
        unawaited(
          _captureViewModel.reportCameraNotFound(
            reason: 'UVC camera permission denied',
            extraInfo: {
              'uvc_vendor_id': device.vendorId,
              'uvc_product_id': device.productId,
              'uvc_name': device.name,
              'source': 'resume_live_feed',
            },
          ),
        );
        return;
      }

      await _openUvcController();
      if (!mounted) return;
      if (_uvcController == null &&
          _uvcPhase == UvcFeedPhase.live &&
          _uvcError == null) {
        _uvcPhase = UvcFeedPhase.error;
        setState(() {
          _uvcError = 'USB camera did not reopen. Tap Retry USB camera.';
        });
        unawaited(
          _captureViewModel.reportCameraNotFound(
            reason: 'UVC camera failed to reopen',
            extraInfo: {
              'uvc_vendor_id': device.vendorId,
              'uvc_product_id': device.productId,
              'uvc_name': device.name,
              'source': reason,
            },
          ),
        );
      }
    } catch (e, st) {
      AppLogger.error('UVC resume live feed failed ($reason)', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _uvcPhase = UvcFeedPhase.error;
        _uvcError = cameraLoadFailureMessage(e);
        _uvcInitializing = false;
      });
    } finally {
      _uvcReconnectInFlight = false;
      if (mounted) {
        setState(() => _uvcInitializing = false);
      }
    }
  }

  Future<void> _disposeUvc() async {
    _resetUvcLiveFeedSessionFlags();
    await _closeUvcController();
    _clearUvcBindingState();
  }

  /// Teardown when leaving capture — bypasses [_withUvcLock] so Continue cannot
  /// block behind a slow in-flight UVC open/capture.
  Future<void> _disposeUvcForNavigation() async {
    _resetUvcLiveFeedSessionFlags();
    await _closeUvcControllerUnlocked();
    _clearUvcBindingState();
  }

  void _clearUvcBindingState() {
    _uvcDevice = null;
    _uvcError = null;
    _uvcPreviewGeneration = 0;
    _resetUvcAutoReconnectAttempts();
    _uvcReconnectInFlight = false;
  }

  bool get _isUsingUvc => _uvcDevice != null;

  void _attachUvcDeviceEvents() {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _uvcDeviceEventsSub?.cancel();
    _uvcDeviceEventsSub = UvcDeviceEventHub.instance.listen(
      _onUvcDeviceEvent,
      onError: (err, st) {
        AppLogger.error('UVC deviceEventStream error', error: err, stackTrace: st);
      },
    );
  }

  void _onUvcDeviceEvent(UvcCameraDeviceEvent event) {
    if (_uvcDevice == null) {
      if (_skipUvcForCameraXSession) return;
      if (event.type == UvcCameraDeviceEventType.attached ||
          event.type == UvcCameraDeviceEventType.connected) {
        _safeUnawaited(
          _tryBindUvcFromHotplug(event.device),
          label: 'UVC hotplug bind failed',
        );
      }
      return;
    }

    final bound = _uvcDevice;
    if (bound == null || !uvcDeviceMatches(event.device, bound)) return;

    AppLogger.debug(
      'UVC device event: ${event.type.name} '
      'name="${event.device.name}" vid=${event.device.vendorId} pid=${event.device.productId}',
    );

    switch (event.type) {
      case UvcCameraDeviceEventType.attached:
        if (_uvcMayAutoOpenLiveFeed &&
            _uvcController == null &&
            !_uvcBlocksConcurrentAutoOpen) {
          _scheduleUvcReconnect('attached');
        }
      case UvcCameraDeviceEventType.connected:
        // Do not open UVC here — that races Canon LV arm and shows blank HDMI.
        // Route through reconnect so LV is ensured first.
        if (_uvcMayAutoOpenLiveFeed &&
            _uvcController == null &&
            !_uvcBlocksConcurrentAutoOpen) {
          _scheduleUvcReconnect('connected');
        }
      case UvcCameraDeviceEventType.disconnected:
      case UvcCameraDeviceEventType.detached:
        if (_shouldIgnoreUvcDisconnectEvent) {
          AppLogger.debug(
            'UVC ${event.type.name} ignored (intentional close / in flight)',
          );
          return;
        }
        unawaited(() async {
          await _closeUvcController();
          if (!mounted) return;
          setState(() {
            _uvcInitializing = true;
            _uvcOpeningController = false;
            _uvcError = null;
          });
          _scheduleUvcReconnect(event.type.name);
        }());
    }
  }

  void _scheduleUvcReconnect(String reason) {
    if (!_isUsingUvc ||
        !_uvcMayAutoOpenLiveFeed ||
        _uvcBlocksConcurrentAutoOpen ||
        _uvcReconnectInFlight) {
      return;
    }
    if (!uvcMayScheduleAutoReconnect(
      attemptCount: _uvcAutoReconnectAttempts,
      maxAttempts: UvcCaptureConfig.maxAutoReconnectAttempts,
    )) {
      _markUvcReconnectExhausted();
      return;
    }

    _uvcAutoReconnectAttempts++;
    _uvcReconnectTimer?.cancel();
    final delay = uvcReconnectBackoffDelay(_uvcAutoReconnectAttempts);
    _uvcReconnectTimer = Timer(delay, () {
      if (!mounted) return;
      if (_uvcDevice == null ||
          _uvcController != null ||
          !_uvcMayAutoOpenLiveFeed ||
          _uvcBlocksConcurrentAutoOpen ||
          _uvcReconnectInFlight) {
        return;
      }
      AppLogger.debug(
        'UVC reconnect scheduled ($reason) attempt=$_uvcAutoReconnectAttempts '
        'delayMs=${delay.inMilliseconds}',
      );
      _safeUnawaited(
        _resumeUvcLiveFeed(reason: reason),
        label: 'UVC reconnect failed',
      );
    });
  }

  /// Binds [device] for live preview. Returns false when bind is skipped (e.g.
  /// a route-prefilled still is still set).
  Future<bool> _bindUvcDevice(UvcCameraDevice device) async {
    if (_uvcCaptureInFlight || _captureViewModel.capturedPhoto != null) {
      return false;
    }

    _captureViewModel.applyDefaultPreviewRotationForUvc();
    await _captureViewModel.disposeCamera();

    if (!mounted) return false;
    setState(() {
      _uvcDevice = device;
      _uvcError = null;
    });

    final ok = await ensureUvcPermissions(device);
    if (!mounted) return false;
    if (!ok) {
      setState(() {
        _uvcDevice = null;
        _uvcInitializing = false;
        _uvcError = 'USB camera permission was not granted.';
      });
      unawaited(
        _captureViewModel.reportCameraNotFound(
          reason: 'UVC camera permission denied',
          extraInfo: {
            'uvc_vendor_id': device.vendorId,
            'uvc_product_id': device.productId,
            'uvc_name': device.name,
          },
        ),
      );
      return false;
    }

    await _armCanonLiveViewForPose();
    if (!mounted) return false;
    await _openUvcController();
    if (!mounted) return false;
    if (_uvcController?.value.isInitialized != true) {
      setState(() {
        _uvcDevice = null;
        _uvcInitializing = false;
      });
      return false;
    }
    _stopUvcEntryProbe();
    return true;
  }

  /// Opens UVC when connected; clears stale FotoZen route prefill once so POSE
  /// always gets a live feed after "Start all over again" or similar re-entry.
  /// Never discards a Classic review still — USB webcam reconnect churn was
  /// clearing 1-shot captures and restarting the auto countdown loop.
  Future<bool> _ensureUvcDeviceBound(UvcCameraDevice device) async {
    if (await _bindUvcDevice(device)) return true;
    if (_captureViewModel.capturedPhoto == null) return false;
    if (widget.sessionKind.isClassic ||
        _uvcPhase == UvcFeedPhase.reviewing ||
        _stripShots.isNotEmpty) {
      return false;
    }
    _captureViewModel.clearCapturedPhoto();
    return _bindUvcDevice(device);
  }

  Future<void> _openUvcController() async {
    await _withUvcLock(() async {
      final device = _uvcDevice;
      if (device == null || !mounted) return;
      if (_uvcOpeningController || !_uvcMayAutoOpenLiveFeed) {
        return;
      }
      if (_isWithinUvcShutterGrace) {
        return;
      }
      if (_uvcController != null && _uvcController!.value.isInitialized) return;

      _uvcOpeningController = true;
      await _closeUvcControllerUnlocked();
      if (!mounted) {
        return;
      }

      setState(() {
        _uvcInitializing = true;
        _uvcError = null;
      });

      UvcCameraController? opened;
      UvcCameraController? pending;
      try {
        pending = UvcCameraController(
          device: device,
          resolutionPreset: UvcCaptureConfig.resolutionPresetFor(
            _captureViewModel.deviceType,
            preferStripPrintQuality:
                _captureViewModel.preferStripPrintQuality,
          ),
        );
        await pending.initialize().timeout(
          UvcCaptureConfig.openTimeout,
          onTimeout: () => throw TimeoutException('UVC controller initialize'),
        );
        if (!mounted) return;
        await _captureViewModel.refreshDisplayRotation();
        if (!mounted) return;
        opened = pending;
        pending = null;
        final ctrl = opened;
        _uvcPreviewGeneration++;
        _uvcFeedAsleep = false;
        _armUvcPreviewWarmup();
        setState(() {
          _uvcController = ctrl;
          _uvcInitializing = false;
          _uvcError = null;
          _uvcPhase = UvcFeedPhase.live;
        });
        _attachUvcHardwareListeners(ctrl);
        await _setUvcShutterKeysEnabled(true);
        UvcSessionCoordinator.markSessionStarted();
        _armUvcSessionRecycleTimer();
        _resetUvcAutoReconnectAttempts();
        _captureViewModel.markCameraAvailabilityRestored();
        if (kioskShouldTryUvcBeforeCameraX(_captureViewModel.deviceType)) {
          unawaited(_releaseCameraXForUvcSession());
        }
        unawaited(_captureViewModel.warmUpCaptureShutterSound());
        AppLogger.debug(
          'UVC preview opened preset='
          '${UvcCaptureConfig.resolutionPresetFor(
            _captureViewModel.deviceType,
            preferStripPrintQuality:
                _captureViewModel.preferStripPrintQuality,
          ).name} '
          'stripQ=${_captureViewModel.preferStripPrintQuality} '
          'gen=$_uvcPreviewGeneration',
        );
      } catch (e, st) {
        final pendingCtrl = pending;
        if (pendingCtrl != null) {
          try {
            await pendingCtrl.dispose();
          } catch (_) {
            // Best-effort cleanup after a failed open.
          }
        }
        AppLogger.error('UVC open failed (main preview)', error: e, stackTrace: st);
        if (!mounted) return;
        setState(() {
          _uvcInitializing = false;
          _uvcPhase = UvcFeedPhase.error;
          _uvcError = cameraLoadFailureMessage(e);
        });
        unawaited(
          _captureViewModel.reportCameraNotFound(
            reason: 'UVC camera failed to open',
            error: e,
            stackTrace: st,
            extraInfo: {
              'uvc_vendor_id': device.vendorId,
              'uvc_product_id': device.productId,
              'uvc_name': device.name,
            },
          ),
        );
      } finally {
        _uvcOpeningController = false;
        if (mounted && opened == null) {
          setState(() => _uvcInitializing = false);
        }
      }
    });
  }

  Future<void> _setUvcShutterKeysEnabled(bool enabled) async {
    if (_uvcShutterKeysEnabled == enabled) return;
    _uvcShutterKeysEnabled = enabled;
    await HardwareKeyService.setUvcShutterKeysEnabled(enabled);
  }

  void _detachUvcHardwareListeners() {
    _uvcButtonSub?.cancel();
    _uvcButtonSub = null;
    _uvcStatusSub?.cancel();
    _uvcStatusSub = null;
    _uvcErrorSub?.cancel();
    _uvcErrorSub = null;
  }

  void _triggerUvcCapture({
    required String source,
    int button = 0,
    int state = 1,
    bool externalSignal = false,
  }) {
    AppLogger.debug('UVC shutter signal source=$source btn=$button state=$state');
    if (!mounted) return;
    if (_captureViewModel.isCountingDown ||
        _captureViewModel.isCapturing ||
        _uvcCaptureInFlight) {
      return;
    }
    // Classic 1-shot: external shutter only from idle (not needsGuest retries).
    if (widget.sessionKind.isClassicOneShot) {
      if (!classicOneShotMayAcceptExternalShutter(_oneShotPhase)) {
        AppLogger.debug(
          'UVC shutter ignored for Classic 1-shot phase=$_oneShotPhase',
        );
        return;
      }
      _lastUvcShutterAt = DateTime.now();
      _armUvcShutterGrace();
      _oneShotRequestGuestCapture();
      return;
    }
    if (!widget.sessionKind.isClassic && _fotoZenCaptureLocked) {
      AppLogger.debug('UVC shutter ignored: FotoZen capture already locked');
      return;
    }
    if (_uvcHoldLiveFeedClosed) {
      return;
    }
    if (_uvcController == null || !_uvcController!.value.isInitialized) {
      return;
    }
    if (_uvcPreviewWarmupActive && externalSignal) {
      AppLogger.debug('UVC shutter ignored during preview warmup source=$source');
      return;
    }
    if (!shouldTriggerUvcShutterCapture(
      button: button,
      state: state,
      lastCaptureAt: _lastUvcShutterAt,
      externalSignal: externalSignal,
    )) {
      return;
    }
    _lastUvcShutterAt = DateTime.now();
    _armUvcShutterGrace();
    _uvcReconnectTimer?.cancel();
    _cancelUvcIdleSleepTimer();
    _uvcFeedAsleep = false;
    if (!widget.sessionKind.isClassic) {
      _fotoZenCaptureLocked = true;
    }
    unawaited(_captureUvc(_captureViewModel, source: source));
  }

  void _attachUvcHardwareListeners(UvcCameraController ctrl) {
    _detachUvcHardwareListeners();
    if (!ctrl.value.isInitialized) {
      AppLogger.debug('UVC hardware listeners skipped: controller not initialized');
      return;
    }
    try {
      _attachUvcControllerListener(ctrl);
      _uvcButtonSub = ctrl.cameraButtonEvents.listen(
        (event) {
          _triggerUvcCapture(
            source: 'uvc_button',
            button: event.button,
            state: event.state,
          );
        },
        onError: (Object e, StackTrace st) {
          AppLogger.error('UVC button stream error', error: e, stackTrace: st);
        },
      );
      _uvcStatusSub = ctrl.cameraStatusEvents.listen(
        (event) {
          AppLogger.debug(
            'UVC status class=${event.payload.statusClass.name} '
            'event=${event.payload.event} selector=${event.payload.selector}',
          );
        },
        onError: (Object e, StackTrace st) {
          AppLogger.error('UVC status stream error', error: e, stackTrace: st);
        },
      );
      _uvcErrorSub = ctrl.cameraErrorEvents.listen(
        (event) {
          if (event.error.type != UvcCameraErrorType.previewInterrupted) return;
          AppLogger.debug(
            'UVC previewInterrupted reason=${event.error.reason}',
          );
          if (_shouldIgnorePreviewInterrupt(event.error)) {
            AppLogger.debug('UVC previewInterrupted ignored');
            return;
          }
          // Capture cards pause HDMI often; never treat as shutter (see
          // shouldTreatUvcPreviewInterruptAsShutter). Body shutter uses uvc_button.
          if (!shouldTreatUvcPreviewInterruptAsShutter()) {
            AppLogger.debug(
              'UVC previewInterrupted ignored (not a shutter signal)',
            );
            return;
          }
          if (widget.sessionKind.isClassicOneShot) {
            if (!classicOneShotMayAcceptExternalShutter(_oneShotPhase)) {
              return;
            }
            _lastUvcShutterAt = DateTime.now();
            _armUvcShutterGrace();
            _oneShotRequestGuestCapture();
            return;
          }
          if (!shouldTriggerUvcShutterFromInterrupt(
            lastCaptureAt: _lastUvcShutterAt,
          )) {
            return;
          }
          _lastUvcShutterAt = DateTime.now();
          _armUvcShutterGrace();
          _uvcReconnectTimer?.cancel();
          unawaited(_captureUvc(
            _captureViewModel,
            source: 'preview_interrupt',
          ));
        },
        onError: (Object e, StackTrace st) {
          AppLogger.error('UVC error stream error', error: e, stackTrace: st);
        },
      );
    } catch (e, st) {
      AppLogger.error(
        'UVC hardware listeners unavailable; preview continues without them',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _showCameraSelectionDialog(
    BuildContext context,
    CaptureViewModel viewModel,
  ) async {
    final picked = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => PhotoCaptureCameraPickerScreen(viewModel: viewModel),
      ),
    );
    if (!mounted || picked == null) return;

    if (picked is CameraDescription) {
      await _disposeUvc();
      await viewModel.switchCamera(picked);
      return;
    }

    if (picked is UvcCameraDevice) {
      await _ensureUvcDeviceBound(picked);
    }
  }

  Size? _uvcPreviewDisplaySize(CaptureViewModel viewModel) {
    final mode = _uvcController?.value.previewMode;
    if (mode == null) return null;
    return viewModel.uvcPreviewDisplaySizeForCard(
      frameWidth: mode.frameWidth.toDouble(),
      frameHeight: mode.frameHeight.toDouble(),
    );
  }

  bool _isUvcSavingStill(CaptureViewModel viewModel) =>
      uvcShouldMaskHdmiDuringStill(
        hasCapturedPhoto: viewModel.capturedPhoto != null,
        isCapturing: viewModel.isCapturing,
        captureInFlight: _uvcCaptureInFlight,
        hdmiStillMaskArmed: _uvcHdmiStillMaskArmed,
        isCountingDown: viewModel.isCountingDown,
        countdownValue: viewModel.countdownValue,
      );

  Widget _uvcSavingPhotoCard() {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 12),
            Text(
              AppStrings.captureCapturingPhoto,
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  /// Opaque card while HDMI may still show the Canon body status LCD (ISO / Q).
  Widget _uvcStartingLiveViewCard() {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 12),
            Text(
              AppStrings.captureStartingPreview,
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUvcPreview(BuildContext context, CaptureViewModel viewModel) {
    if (viewModel.isSelectingFromGallery) {
      return buildGallerySelectionPlaceholder();
    }

    final saving = _isUvcSavingStill(viewModel);
    // Full black during shutter — dim-over-live showed Canon's HDMI status LCD
    // (P / ISO / Q) after gphoto drops Live View for the still.
    if (saving) {
      return _uvcSavingPhotoCard();
    }
    // First HDMI frames after open are often the body info screen until LV
    // settles — mask until warmup ends.
    if (_uvcPreviewWarmupActive && viewModel.capturedPhoto == null) {
      return _uvcStartingLiveViewCard();
    }

    if (_uvcFeedAsleep) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(_wakeUvcFromIdleSleep()),
        child: const ColoredBox(
          color: Colors.black,
          child: Center(
            child: Text(
              AppStrings.uvcTapToWakePreview,
              style: TextStyle(color: Colors.white70, fontSize: 16, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final ctrl = _uvcController;
    if (_uvcInitializing) {
      final message = _uvcAutoReconnectAttempts > 0
          ? AppStrings.uvcReconnectingMessage
          : 'Connecting USB camera…';
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 12),
              Text(
                message,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    if (_uvcError != null) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _uvcError!,
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _uvcInitializing || _uvcOpeningController
                      ? null
                      : () => _safeUnawaited(
                            _resumeUvcLiveFeed(reason: 'retryTap'),
                            label: 'UVC retry open failed',
                          ),
                  child: const Text('Retry USB camera'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (ctrl == null || !ctrl.value.isInitialized) {
      // Prefer "Saving…" over "Connecting…" while a still is in flight and the
      // controller was already closed for review.
      return saving
          ? _uvcSavingPhotoCard()
          : const ColoredBox(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 12),
                    Text(
                      'Connecting USB camera…',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            );
    }

    return ValueListenableBuilder<UvcCameraControllerState>(
      valueListenable: ctrl,
      builder: (context, state, _) {
        if (!state.isInitialized) {
          return saving
              ? _uvcSavingPhotoCard()
              : const ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 12),
                        Text(
                          'Connecting USB camera…',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                );
        }

        final previewMode = state.previewMode;
        final frameWidth = previewMode?.frameWidth.toDouble() ?? 1.0;
        final frameHeight = previewMode?.frameHeight.toDouble() ?? 1.0;
        final baseAspect = frameWidth / frameHeight;
        final effectiveTurns = viewModel.uvcPreviewEffectiveQuarterTurns;

        final live = KeyedSubtree(
          key: ValueKey<int>(_uvcPreviewGeneration),
          child: RepaintBoundary(
            key: _uvcPreviewBoundaryKey,
            child: buildRotatedCoverPreview(
              preview: ctrl.buildPreview(),
              effectiveQuarterTurns: effectiveTurns,
              baseAspectRatio: baseAspect <= 0 ? 1.0 : baseAspect,
              frameSize: Size(frameWidth, frameHeight),
            ),
          ),
        );
        return live;
      },
    );
  }

  Future<void> _captureUvc(
    CaptureViewModel viewModel, {
    required String source,
  }) async {
    // HDMI capture-card pauses must never start a still.
    if (source == 'preview_interrupt' &&
        !shouldTreatUvcPreviewInterruptAsShutter()) {
      AppLogger.debug('UVC capture blocked: preview_interrupt is not a shutter');
      return;
    }
    // Classic 1-shot may only shutter from the FSM countdown path.
    if (widget.sessionKind.isClassicOneShot &&
        source != 'classic_one_shot' &&
        _oneShotPhase != ClassicOneShotPhase.counting &&
        _oneShotPhase != ClassicOneShotPhase.capturing) {
      AppLogger.debug(
        'UVC capture blocked for Classic 1-shot source=$source '
        'phase=$_oneShotPhase',
      );
      return;
    }
    final device = _uvcDevice;
    if (device == null ||
        _uvcPhase == UvcFeedPhase.capturing ||
        _uvcPhase == UvcFeedPhase.reviewing ||
        viewModel.capturedPhoto != null ||
        viewModel.isCapturing) {
      return;
    }

    final cameraId =
        'uvc:${device.vendorId}:${device.productId}:${device.name}';
    XFile? capturedFile;
    var captureFailed = false;
    var fromSidecar = false;

    await _withUvcLock(() async {
      final ctrl = _uvcController;
      if (ctrl == null ||
          _uvcDevice == null ||
          _uvcPhase == UvcFeedPhase.capturing ||
          _uvcPhase == UvcFeedPhase.reviewing ||
          viewModel.capturedPhoto != null ||
          viewModel.isCapturing) {
        return;
      }
      if (!isUvcShutterCaptureSource(source) && !_uvcReadyForCapture) {
        return;
      }
      if (source == 'ui_button' && _uvcLastUiCaptureEndedAt != null) {
        final elapsed = DateTime.now().difference(_uvcLastUiCaptureEndedAt!);
        const cooldown = UvcCaptureConfig.uiCaptureCooldown;
        if (elapsed < cooldown) {
          await Future<void>.delayed(cooldown - elapsed);
          if (!mounted) return;
        }
      }
      if (isUvcShutterCaptureSource(source) &&
          (ctrl.value.isInitialized != true || _uvcBlocksConcurrentAutoOpen)) {
        return;
      }

      // Sidecar still + HDMI pose: never shoot while Canon LV is not held —
      // that races ensureLiveView and causes PTP Timeout on the Pi.
      final sidecarConfigured =
          _captureViewModel.localCameraService?.isConfigured == true;
      if (sidecarConfigured && !_canonLvHolding) {
        AppLogger.warning(
          '[HDMI_POSE] UVC capture blocked source=$source — Canon LV not holding',
        );
        unawaited(
          _captureViewModel.localCameraService?.postClientEvent(
            'capture_blocked_no_lv',
            {'source': source},
          ),
        );
        return;
      }

      if (isUvcShutterCaptureSource(source)) {
        final now = DateTime.now();
        if (_lastUvcShutterAt != null &&
            now.difference(_lastUvcShutterAt!) < kUvcShutterDebounce) {
          AppLogger.debug('UVC capture debounced source=$source');
          return;
        }
        _lastUvcShutterAt = now;
        _armUvcShutterGrace();
      }

      _uvcPhase = UvcFeedPhase.capturing;
      _uvcCaptureInFlight = true;
      _uvcReconnectTimer?.cancel();
      _cancelUvcIdleSleepTimer();
      if (mounted) setState(() {});

      try {
        AppLogger.debug('UVC capture start source=$source');
        // DSLR body already clicks on sidecar still — skip synthetic flash/SFX
        // so the booth does not stack white flash + mirror clicks + LCD flap.
        final preferSidecar =
            _captureViewModel.localCameraService?.isConfigured == true;
        if (preferSidecar) {
          _armUvcHdmiStillMask();
        } else {
          await _pulseCaptureFlash(playSound: true);
        }
        final previewMode = ctrl.value.previewMode;
        if (previewMode != null) {
          final displaySize = viewModel.uvcPreviewDisplaySizeForCard(
            frameWidth: previewMode.frameWidth.toDouble(),
            frameHeight: previewMode.frameHeight.toDouble(),
          );
          if (displaySize != null && displaySize.height > 0) {
            viewModel.lockCaptureCardAspectRatio(
              displaySize.width / displaySize.height,
            );
          }
        }

        if (!isUvcShutterCaptureSource(source)) {
          await Future<void>.delayed(UvcCaptureConfig.preCaptureSettleDelay);
        }
        await Future<void>.delayed(Duration.zero);
        // Classic 1-shot leaves for looks — no next HDMI pose, so skip LV re-arm
        // (avoids stacked mirror clicks under Saving…).
        final resumeLvAfterStill = !widget.sessionKind.isClassicOneShot;
        final sidecar = await tryCaptureFromSidecar(
          _captureViewModel.localCameraService,
          resumeLiveView: resumeLvAfterStill,
        );
        if (sidecar != null) {
          fromSidecar = true;
          capturedFile = sidecar;
          AppLogger.info('UVC pose shutter used Pi sidecar still');
          // Sidecar already restarted the LV keeper when resumeLiveView=true.
          // A second Flutter ensure would stop/start it again (extra clicks).
        } else if (preferSidecar) {
          // Never grab a blank HDMI/UVC frame when the Pi DSLR path is configured —
          // that is what advanced the booth with a black still after PTP Timeout.
          captureFailed = true;
          AppLogger.error(
            '[HDMI_POSE] Sidecar still failed; refusing blank UVC fallback '
            'source=$source',
          );
          unawaited(
            _captureViewModel.localCameraService?.postClientEvent(
              'capture_refused_uvc_fallback',
              {'source': source},
            ),
          );
          if (mounted) {
            _uvcPhase = UvcFeedPhase.error;
            setState(() {
              _uvcError =
                  'Camera capture failed. Check the DSLR USB link, then tap Retry.';
            });
          }
          return;
        } else {
          capturedFile = await _obtainUvcStillFile(ctrl, source: source);
        }
        if (mounted) setState(() => _showCaptureFlash = false);

        // Pi sidecar stills: keep UVC live under the Saving overlay until the
        // review JPEG is assigned — closing first caused a long blank gap
        // (dispose + 750ms delay + Connecting flash).
        if (!UvcCaptureConfig.keepControllerOpenDuringReview && !fromSidecar) {
          _detachUvcHardwareListeners();
          await _closeUvcControllerUnlocked();
          await Future<void>.delayed(UvcCaptureConfig.postDisposeDelay);
          if (mounted) setState(() {});
        }
      } catch (e, st) {
        captureFailed = true;
        AppLogger.error(
          'UVC capture failed source=$source',
          error: e,
          stackTrace: st,
        );
        if (!mounted) return;
        _uvcPhase = UvcFeedPhase.error;
        setState(() {
          _uvcError = isUvcShutterCaptureSource(source)
              ? 'DSLR shutter capture failed. Tap Retry USB camera, or use Capture on screen.'
              : 'USB camera capture failed: $e';
        });
      } finally {
        if (capturedFile == null && !captureFailed) {
          _detachUvcHardwareListeners();
          await _closeUvcControllerUnlocked();
        } else if (captureFailed) {
          _detachUvcHardwareListeners();
          await _closeUvcControllerUnlocked();
        }
        // Hold Saving UI until setCapturedPhotoFromExternalFile finishes when
        // we have a still — clearing here flashed blank Connecting in between.
        if (capturedFile == null || captureFailed) {
          _clearUvcTransientCaptureUi();
        }
        if (mounted) setState(() {});
      }
    });

    if (!mounted || capturedFile == null) {
      return;
    }

    if (mounted) {
      setState(() => _uvcPhase = UvcFeedPhase.reviewing);
    }

    try {
      await viewModel
          .setCapturedPhotoFromExternalFile(
            rawFile: capturedFile!,
            cameraId: fromSidecar ? 'sidecar:FZ200D' : cameraId,
            force: true,
          )
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () {
              throw TimeoutException(
                'Saving photo timed out after sidecar/UVC still',
              );
            },
          );
      if (!mounted) return;
      if (viewModel.capturedPhoto == null) {
        _uvcPhase = UvcFeedPhase.error;
        setState(() {
          _uvcError = viewModel.errorMessage ??
              'USB camera capture failed. Tap Retry USB camera.';
        });
        return;
      }
      _uvcPhase = UvcFeedPhase.reviewing;
      _uvcReconnectTimer?.cancel();
      if (source == 'ui_button') {
        _uvcLastUiCaptureEndedAt = DateTime.now();
      }
      if (mounted) setState(() {});
    } catch (e, st) {
      AppLogger.error(
        'UVC capture normalize failed source=$source',
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      _uvcPhase = UvcFeedPhase.error;
      setState(() {
        _uvcError = 'USB camera capture failed: $e';
      });
    } finally {
      if (!UvcCaptureConfig.keepControllerOpenDuringReview && fromSidecar) {
        _detachUvcHardwareListeners();
        await _closeUvcControllerUnlocked();
      }
      _clearUvcTransientCaptureUi();
      if (mounted) setState(() {});
    }
  }

  Future<void> _openPreviewRotationScreen(BuildContext context, CaptureViewModel viewModel) async {
    final result = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (ctx) => PhotoCaptureRotationScreen(
          currentRotation: viewModel.previewRotationDegrees,
        ),
      ),
    );
    if (result != null && mounted) {
      await viewModel.setPreviewRotation(result);
    }
  }

  Widget _buildNoCamerasYetState(
    BuildContext context,
    CaptureViewModel viewModel,
  ) {
    // Classic strip never offers Gallery / Phone QR mid-session (would break
    // the 4-shot flow and flash wide CTAs during web camera remount).
    final allowGallery = !_isClassicPose &&
        context.select<AppSettingsManager, bool>(
          (m) => m.settings?.photoUploadAllowed == true,
        );
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!allowGallery) ...[
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 16),
            ],
            Text(
              allowGallery
                  ? AppStrings.captureNoCameraUploadHint
                  : (_isFlashbackFourShot
                      ? AppStrings.flashbackGettingReadyNextShot
                      : 'Waiting for camera…'),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => _resetAndInitializeCameras(forceRefresh: true),
              child: const Text('Retry camera'),
            ),
            if (allowGallery) ...[
              const SizedBox(height: 20),
              _buildNoCameraUploadActions(context, viewModel),
            ],
          ],
        ),
      ),
    );
  }

  /// Gallery + Phone QR when the live camera path is unavailable.
  Widget _buildNoCameraUploadActions(
    BuildContext context,
    CaptureViewModel viewModel,
  ) {
    final busy = viewModel.isSelectingFromGallery ||
        viewModel.isWaitingForPhoneUpload;
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            style: captureScreenButtonStyle(secondary: true),
            onPressed: busy
                ? null
                : () async => _handleSelectFromGallery(viewModel),
            icon: const Icon(CupertinoIcons.photo, size: 20),
            label: Text(
              viewModel.isSelectingFromGallery
                  ? 'Selecting…'
                  : AppStrings.galleryButtonLabel,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: captureScreenButtonStyle(secondary: true),
            onPressed: busy
                ? null
                : () async {
                    await showPhoneUploadQrSheet(
                      context: context,
                      viewModel: viewModel,
                    );
                  },
            icon: const Icon(CupertinoIcons.qrcode, size: 20),
            label: Text(
              viewModel.isWaitingForPhoneUpload
                  ? AppStrings.phoneUploadWaiting
                  : AppStrings.phoneUploadButtonLabel,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartingCameraState({String message = AppStrings.captureStartingPreview}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 20),
          Text(
            message,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureFatalErrorState(
    BuildContext context,
    CaptureViewModel viewModel,
  ) {
    final appColors = AppColors.of(context);
    final allowGallery = !_isClassicPose &&
        context.select<AppSettingsManager, bool>(
          (m) => m.settings?.photoUploadAllowed == true,
        );
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: 64,
              color: appColors.errorColor,
            ),
            const SizedBox(height: 16),
            Text(
              viewModel.errorMessage ?? 'Unknown error',
              style: const TextStyle(fontSize: 16, color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () =>
                      _resetAndInitializeCameras(forceRefresh: true),
                  child: const Text('Retry'),
                ),
                TextButton(
                  onPressed: () => openAppSettings(),
                  child: const Text('Open Settings'),
                ),
              ],
            ),
            if (allowGallery) ...[
              const SizedBox(height: 20),
              _buildNoCameraUploadActions(context, viewModel),
            ],
          ],
        ),
      ),
    );
  }

  bool get _uvcHoldLivePreviewClosed =>
      uvcFeedPhaseBlocksLivePreview(_uvcPhase);

  bool _isCapturePreviewStarting(CaptureViewModel viewModel) {
    final setupStalled = _uvcError != null &&
        !_uvcFeedIsHealthy &&
        !viewModel.isReady &&
        !viewModel.isLoadingCameras &&
        !viewModel.isInitializing;
    return isCapturePreviewStarting(
      hasCapturedPhoto: viewModel.capturedPhoto != null,
      isDesktopCaptureMode: viewModel.isDesktopCaptureMode,
      isLoadingCameras: viewModel.isLoadingCameras,
      isInitializing: viewModel.isInitializing,
      isCapturing: viewModel.isCapturing || _uvcCaptureInFlight,
      isUsingUvc: _isUsingUvc,
      uvcHoldLivePreviewClosed: _uvcHoldLivePreviewClosed,
      uvcInitializing: _uvcInitializing,
      uvcOpeningController: _uvcOpeningController,
      uvcControllerReady: _uvcController?.value.isInitialized == true,
      camerasEmpty: viewModel.availableCameras.isEmpty,
      isReady: viewModel.isReady,
      cameraSetupStalled: setupStalled,
      usesSidecarLivePreview: viewModel.usesSidecarLivePreview,
    );
  }

  Widget _buildCaptureBodyContent(
    BuildContext context,
    CaptureViewModel viewModel,
  ) {
    if (viewModel.isDesktopCaptureMode) {
      if (viewModel.capturedPhoto == null) {
        final allowGallery = context.select<AppSettingsManager, bool>(
          (m) => m.settings?.photoUploadAllowed == true,
        );
        return PhotoCaptureDesktopBody(
          viewModel: viewModel,
          showGallery: allowGallery,
          onTakePhoto: () => viewModel.capturePhotoFromDesktopPicker(),
          onPickGallery: () => viewModel.selectFromGallery(),
          onPhoneUpload: allowGallery
              ? () {
                  unawaited(
                    showPhoneUploadQrSheet(
                      context: context,
                      viewModel: viewModel,
                    ),
                  );
                }
              : null,
        );
      }
      return Padding(
        padding: const EdgeInsets.only(left: 12, right: 12),
        child: _buildCaptureColumn(
          context: context,
          viewModel: viewModel,
          hasCapturedPhoto: true,
          previewWidget: const SizedBox.shrink(),
        ),
      );
    }

    final phase = resolveCaptureBodyPhase(
      isPreviewStarting: _isCapturePreviewStarting(viewModel),
      camerasEmpty: viewModel.availableCameras.isEmpty,
      hasError: viewModel.hasError,
      isUsingUvc: _isUsingUvc,
      hasCapturedPhoto: viewModel.capturedPhoto != null,
      isSelectingFromGallery: viewModel.isSelectingFromGallery,
      usesSidecarLivePreview: viewModel.usesSidecarLivePreview,
    );

    final midStripRemount =
        _isFlashbackFourShot && _stripShots.isNotEmpty;
    final Widget body;
    final String phaseKey;
    switch (phase) {
      case CaptureBodyPhase.starting:
        final startingMessage = midStripRemount
            ? AppStrings.flashbackGettingReadyNextShot
            : AppStrings.captureStartingPreview;
        phaseKey = 'starting-$startingMessage';
        body = _buildStartingCameraState(message: startingMessage);
      case CaptureBodyPhase.noCameras:
        phaseKey = 'no-cameras';
        body = _buildNoCamerasYetState(context, viewModel);
      case CaptureBodyPhase.error:
        phaseKey = 'error';
        body = _buildCaptureFatalErrorState(context, viewModel);
      case CaptureBodyPhase.live:
        final hasCapturedPhoto = viewModel.capturedPhoto != null;
        final Widget previewWidget;
        if (viewModel.isSelectingFromGallery) {
          previewWidget = buildGallerySelectionPlaceholder();
        } else if (hasCapturedPhoto) {
          // Review still — never mount CameraPreview without a controller.
          previewWidget = const SizedBox.shrink();
        } else if (viewModel.usesSidecarLivePreview &&
            viewModel.localCameraService != null) {
          previewWidget = SidecarLivePreview(
            service: viewModel.localCameraService!,
            paused: viewModel.isCapturing || _uvcCaptureInFlight,
            onFirstFrame: viewModel.markSidecarPreviewReady,
          );
        } else if (_isUsingUvc) {
          previewWidget = _buildUvcPreview(context, viewModel);
        } else if (viewModel.cameraController == null) {
          // Controller briefly null during re-init — never flash Gallery CTAs.
          // "Next shot" copy is only for mid-strip 4-shot remounts (not Classic 1-shot).
          previewWidget = midStripRemount
              ? _buildStartingCameraState(
                  message: AppStrings.flashbackGettingReadyNextShot,
                )
              : _buildStartingCameraState(
                  message: AppStrings.captureStartingPreview,
                );
        } else {
          previewWidget = _buildCameraPreviewWithRotation(context, viewModel);
        }
        phaseKey = hasCapturedPhoto ? 'captured' : 'live';
        body = Padding(
          padding: const EdgeInsets.only(left: 12, right: 12),
          child: _buildCaptureColumn(
            context: context,
            viewModel: viewModel,
            hasCapturedPhoto: hasCapturedPhoto,
            previewWidget: previewWidget,
          ),
        );
    }

    return AnimatedSwitcher(
      duration: kIsWeb ? Duration.zero : const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOut,
      child: KeyedSubtree(
        key: ValueKey<String>(phaseKey),
        child: body,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _captureViewModel,
      child: Consumer<CaptureViewModel>(
        builder: (context, viewModel, child) {
          return ListenableBuilder(
            listenable: AppRuntimeConfig.instance,
            builder: (context, _) {
              return Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _notePoseUserActivity(),
                child: PhotoCaptureScaffold(
                  viewModel: viewModel,
                  subtitleHint: _subtitleHint,
                  stripShotTotal:
                      _isFlashbackFourShot ? _multiShotTotal : null,
                  stripShotFiles: _isFlashbackFourShot
                      ? _stripShots.map((p) => p.imageFile).toList(growable: false)
                      : const [],
                  stripPendingFile: _isFlashbackFourShot
                      ? viewModel.capturedPhoto?.imageFile
                      : null,
                  onBack: () => unawaited(_handleCaptureBack(context)),
                  onSelectCamera: () =>
                      _showCameraSelectionDialog(context, viewModel),
                  onOpenRotation: () =>
                      _openPreviewRotationScreen(context, viewModel),
                  onReloadCameras: () =>
                      _resetAndInitializeCameras(forceRefresh: true),
                  body: Builder(
                    builder: (context) => _buildCaptureBodyContent(
                      context,
                      Provider.of<CaptureViewModel>(context, listen: true),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Column layout for both orientations: info at top, buttons row, preview/photo fills rest.
  Widget _buildCaptureColumn({
    required BuildContext context,
    required CaptureViewModel viewModel,
    required bool hasCapturedPhoto,
    required Widget previewWidget,
  }) {
    final showNativeDetails = !_isUsingUvc &&
        AppConstants.kShowNativeCameraInfoPane &&
        viewModel.nativeCameraDetails != null &&
        !hasCapturedPhoto;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Camera info (pre-capture) or captured photo info (post-capture) at top
        if (showNativeDetails)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildNativeCameraDetailsCard(
              context,
              viewModel.nativeCameraDetails!,
              previewSize: viewModel.previewSize,
              resolutionPreset: viewModel.effectiveResolutionPreset,
              currentZoom: viewModel.currentZoom,
            ),
          ),
        if (hasCapturedPhoto &&
            AppConstants.kShowNativeCameraInfoPane)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (AppConstants.kShowNativeCameraInfoPane)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _effectiveRotationLabel(viewModel),
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
        // 2. Preview or captured photo: same aspect as theme hero card; size capped so landscape matches carousel scale.
        Expanded(
          child: _buildCapturePreviewCard(
            context,
            viewModel,
            previewWidget,
            hasCapturedPhoto,
          ),
        ),
        // 3. Post-capture errors (e.g. upload) above Continue — full-screen branch is skipped when a photo exists.
        if (hasCapturedPhoto && viewModel.hasError && viewModel.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _buildCaptureErrorSection(context, viewModel),
          ),
        // 4. Bottom actions (consistent placement).
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: CenteredMaxWidth(
            maxWidth: 360,
            child: hasCapturedPhoto
                ? _buildCapturedPhotoControlsRow(context, viewModel)
                : _buildGalleryCaptureButtonsRow(context, viewModel),
          ),
        ),
      ],
    );
  }

  /// Preview / captured still: [ThemeCard]-style shell. Card **aspect** follows the stream or file
  /// when known (landscape webcam → landscape frame; portrait → portrait) so web/mobile avoid
  /// heavy letterboxing. Falls back to [AppConstants.themeCardSlotAspectRatio] if size unknown.
  ///
  /// Size is capped on width/height so landscape kiosks get a bounded card.
  Widget _buildCapturePreviewCard(
    BuildContext context,
    CaptureViewModel viewModel,
    Widget previewWidget,
    bool hasCapturedPhoto,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.sizeOf(context);
        final isLandscape =
            MediaQuery.orientationOf(context) == Orientation.landscape;
        final isTablet = media.shortestSide >= AppConstants.kTabletBreakpoint;
        final fallbackAspect = AppConstants.themeCardSlotAspectRatio(context);
        final isPhonePortrait = !isLandscape &&
            media.shortestSide < AppConstants.kTabletBreakpoint;
        final aspect = captureCardAspectRatio(
          context,
          viewModel,
          hasCapturedPhoto,
          fallbackAspect,
          constraints,
          uvcPreviewDisplaySize:
              _isUsingUvc ? _uvcPreviewDisplaySize(viewModel) : null,
        );

        final (widthCapFrac, heightCapFrac) = capturePreviewCardSizeFractions(
          isLandscape: isLandscape,
          isPhonePortrait: isPhonePortrait,
        );

        // Tablets: use the full canvas available for a cleaner kiosk-style preview.
        final maxW = isTablet
            ? constraints.maxWidth
            : math.min(constraints.maxWidth, media.width * widthCapFrac);
        final maxH = isTablet
            ? constraints.maxHeight
            : math.min(constraints.maxHeight, media.height * heightCapFrac);

        final (cardW, cardH) = capturePreviewCardDimensions(
          constraints: constraints,
          aspect: aspect,
          maxW: maxW,
          maxH: maxH,
        );

        return Center(
          child: Card(
            margin: EdgeInsets.zero,
            elevation: 8,
            shadowColor: Colors.black.withValues(alpha: 0.38),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(
                color: Color(0xFF4A4A4A),
                width: 1.5,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: cardW,
              height: cardH,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: Colors.black,
                    child: KeyedSubtree(
                      key: ValueKey<String>(
                        viewModel.capturedPhoto?.id ?? 'live-preview',
                      ),
                      child: viewModel.capturedPhoto != null
                          ? photo_image.imageFromXFileSized(
                              viewModel.capturedPhoto!.imageFile,
                              cardW,
                              cardH,
                              // Match live preview: full frame visible (no cover crop).
                              fit: BoxFit.contain,
                              sharpDisplay: !kioskShouldTryUvcBeforeCameraX(
                                viewModel.deviceType,
                              ),
                            )
                          : KeyedSubtree(
                              // Web builds can aggressively reuse platform views / textures.
                              // Force the camera preview subtree to remount on retake.
                              key: ValueKey<int>(viewModel.previewNonce),
                              child: previewWidget,
                            ),
                    ),
                  ),
                  if (!hasCapturedPhoto &&
                      AppConstants.kShowNativeCameraInfoPane &&
                      (_isUsingUvc || viewModel.previewSize != null))
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _effectiveRotationLabel(viewModel),
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ),
                    ),
                  if (viewModel.isCountingDown)
                    Positioned.fill(
                      child: _buildCountdownOverlay(context, viewModel.countdownValue!),
                    ),
                  if (hasCapturedPhoto &&
                      _isFlashbackMultiShot &&
                      _flashbackReviewEndsAt != null &&
                      !_stripFinishing)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: FlashbackReviewHoldBanner(
                        key: ValueKey<String>(
                          'review-hold-${_flashbackReviewPhotoId ?? _flashbackReviewEndsAt!.millisecondsSinceEpoch}',
                        ),
                        endsAt: _flashbackReviewEndsAt!,
                        isLastShot: (_stripShots.length + 1) >=
                            (_multiShotTotal ?? kStripShotCount),
                      ),
                    ),
                  if (!_showCaptureFlash &&
                      !hasCapturedPhoto &&
                      !_isUsingUvc &&
                      (viewModel.isCapturing || _uvcCaptureInFlight))
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.35),
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  if (_showCaptureFlash)
                    const Positioned.fill(
                      child: ColoredBox(color: Colors.white),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Builds camera preview and applies Android TV/external-camera correction
  /// plus any user-selected manual rotation.
  Widget _buildCameraPreviewWithRotation(BuildContext context, CaptureViewModel viewModel) {
    final controller = viewModel.cameraController;
    if (controller == null) {
      return Container(
        color: AppColors.of(context).backgroundColor,
        child: Center(
          child: Text(
            'Camera preview not available',
            style: TextStyle(color: AppColors.of(context).textColor),
          ),
        ),
      );
    }

    final preview = _buildPlatformPreview(context, viewModel, controller);
    if (!controller.value.isInitialized) {
      return preview;
    }

    final effectiveQuarterTurns =
        (viewModel.previewAutoQuarterTurns +
                (viewModel.previewRotationDegrees ~/ 90) % 4) %
            4;

    // CameraPreview already inverts aspect for portrait and applies Android
    // RotatedBox. Wrapping it in sensor (landscape) AspectRatio squashes phones.
    if (effectiveQuarterTurns == 0) {
      final isLandscapeUi =
          MediaQuery.orientationOf(context) == Orientation.landscape;
      return buildCoverCameraPreview(
        cameraPreview: preview,
        displayAspectRatio: cameraPreviewDisplayAspectRatio(
          controllerAspectRatio: controller.value.aspectRatio,
          isLandscapeUi: isLandscapeUi,
        ),
      );
    }

    return buildRotatedCoverPreview(
      preview: preview,
      effectiveQuarterTurns: effectiveQuarterTurns,
      baseAspectRatio: controller.value.aspectRatio,
      frameSize: controller.value.previewSize,
    );
  }

  Widget _buildPlatformPreview(
    BuildContext context,
    CaptureViewModel viewModel,
    CameraController controller,
  ) {
    if (!controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return CameraPreview(
      controller,
      key: ValueKey<String>(
        '${viewModel.cameraGeneration}-${viewModel.previewNonce}',
      ),
    );
  }

  String _effectiveRotationLabel(CaptureViewModel viewModel) {
    if (_isUsingUvc) {
      final autoTurns = viewModel.uvcPreviewAutoQuarterTurns;
      final manualTurns = (viewModel.previewRotationDegrees ~/ 90) % 4;
      final effectiveTurns = (autoTurns + manualTurns) % 4;
      final rotation =
          '${effectiveTurns * 90}° (auto ${autoTurns * 90}° + manual ${manualTurns * 90}°)';
      final mode = _uvcController?.value.previewMode;
      if (mode != null) {
        return '$rotation • ${mode.frameWidth}×${mode.frameHeight}';
      }
      return '$rotation • USB';
    }

    final autoTurns = viewModel.previewAutoQuarterTurns;
    final manualTurns = (viewModel.previewRotationDegrees ~/ 90) % 4;
    final effectiveTurns = (autoTurns + manualTurns) % 4;
    final rotation = '${effectiveTurns * 90}° (auto ${autoTurns * 90}° + manual ${manualTurns * 90}°)';
    final size = viewModel.previewSize;
    if (size != null) {
      return '$rotation • ${size.width.toInt()}×${size.height.toInt()}';
    }
    return rotation;
  }

  /// Native camera details pane (preview size, active array, zoom, etc.). Shown until photo is captured.
  Widget _buildNativeCameraDetailsCard(
    BuildContext context,
    CameraDetails details, {
    Size? previewSize,
    ResolutionPreset? resolutionPreset,
    double? currentZoom,
  }) {
    const style = TextStyle(color: Colors.white70, fontSize: 11);
    const labelStyle = TextStyle(color: Colors.white54, fontSize: 10);
    final inUseW = previewSize?.width.toInt();
    final inUseH = previewSize?.height.toInt();
    final presetName = resolutionPreset?.name ?? '?';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      constraints: const BoxConstraints(maxWidth: 260),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Native camera (${details.platform})', style: style.copyWith(fontWeight: FontWeight.w600)),
          if (inUseW != null && inUseH != null)
            _detailRow('Preview in use', '$inUseW×$inUseH ($presetName)', labelStyle, style),
          if (currentZoom != null)
            _detailRow('Current zoom', '${currentZoom.toStringAsFixed(2)}x', labelStyle, style),
          const SizedBox(height: 6),
          if (details.activeArrayWidth != null && details.activeArrayHeight != null)
            _detailRow('Active array', '${details.activeArrayWidth}×${details.activeArrayHeight}', labelStyle, style),
          if (details.zoomRatioRangeMin != null && details.zoomRatioRangeMax != null)
            _detailRow('Zoom ratio', '${details.zoomRatioRangeMin!.toStringAsFixed(2)} – ${details.zoomRatioRangeMax!.toStringAsFixed(2)}', labelStyle, style),
          if (details.maxDigitalZoom != null)
            _detailRow('Max digital zoom', details.maxDigitalZoom!.toStringAsFixed(2), labelStyle, style),
          if (details.lensFacing != null)
            _detailRow('Lens facing', details.lensFacing!, labelStyle, style),
          const SizedBox(height: 4),
          Text('Preview sizes (${details.supportedPreviewSizes.length})', style: labelStyle),
          Text(details.supportedPreviewSizes.isEmpty ? '—' : details.supportedPreviewSizes.join(', '), style: style),
          const SizedBox(height: 2),
          Text('Capture sizes (${details.supportedCaptureSizes.length})', style: labelStyle),
          Text(details.supportedCaptureSizes.isEmpty ? '—' : details.supportedCaptureSizes.join(', '), style: style),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, TextStyle labelStyle, TextStyle valueStyle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: labelStyle)),
          Expanded(child: Text(value, style: valueStyle)),
        ],
      ),
    );
  }

  /// Builds the on-screen capture countdown overlay (e.g. 5, 4, 3…).
  Widget _buildCountdownOverlay(BuildContext context, int countdownValue) {
    final flashback = _isClassicPose;
    final total = _isFlashbackSingleShot ? 1 : (_classicShotCap > 0 ? _classicShotCap : kStripShotCount);
    final shotNumber = (_stripShots.length + 1).clamp(1, total);
    final showAiIntro = !flashback &&
        countdownValue == AppConstants.kCaptureCountdownSeconds;
    final headline = flashback
        ? (_isFlashbackSingleShot
            ? AppStrings.flashbackSingle6x4Title
            : AppStrings.flashbackShotProgress(shotNumber, total))
        : (showAiIntro ? AppStrings.captureCountdownIntro : null);

    return Container(
      color: Colors.black.withValues(alpha: 0.5),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (headline != null) ...[
              Text(
                headline,
                style: TextStyle(
                  fontSize: flashback ? 28 : 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.95),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
            ],
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.7),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 30,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  '$countdownValue',
                  style: const TextStyle(
                    fontSize: 80,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Retake and Continue buttons in a Row (post-capture).
  Widget _buildCapturedPhotoControlsRow(BuildContext context, CaptureViewModel viewModel) {
    final multi = _isClassicPose;
    final total = _isFlashbackSingleShot
        ? 1
        : (_classicShotCap > 0 ? _classicShotCap : kStripShotCount);
    final isLastStripShot = multi && (_stripShots.length + 1) >= total;
    final continueLabel = !multi
        ? (viewModel.isPreparingUploadPayload ? 'Preparing…' : 'Continue')
        : (isLastStripShot
            ? AppStrings.flashbackContinueLooks
            : AppStrings.flashbackNextShot);
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton(
            style: captureScreenButtonStyle(secondary: true),
            onPressed: _stripFinishing
                ? null
                : () {
                    _cancelFlashbackAutoTimers();
                    unawaited(_handleRetake(context));
                  },
            child: Text(
              _isFlashbackFourShot
                  ? AppStrings.flashbackRetakeLast
                  : 'Retake',
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            style: captureScreenButtonStyle(),
            onPressed: (!viewModel.canContinueUpload || _stripFinishing)
                ? null
                : () async {
                    if (multi) {
                      _cancelFlashbackAutoTimers();
                      await _acceptFlashbackShot(viewModel);
                      return;
                    }
                    _navigatingAwayFromCapture = true;
                    _stopPoseIdleTimer();
                    await handleCapturedPhotoContinue(
                      context: context,
                      viewModel: viewModel,
                      isMounted: () => mounted,
                      releaseCaptureHardware: _releaseCaptureHardware,
                      returnPhotoOnly: _returnPhotoOnly,
                    );
                  },
            child: (viewModel.isUploading || _stripFinishing)
                ? Text(
                    _stripFinishing
                        ? AppStrings.flashbackPreparingPreview
                        : 'Processing…',
                  )
                : Text(continueLabel),
          ),
        ],
      ),
    );
  }

  /// Error message + Dismiss, shown inside blue box when capture has error.
  Widget _buildCaptureErrorSection(BuildContext context, CaptureViewModel viewModel) {
    final appColors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: appColors.errorColor.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(CupertinoIcons.exclamationmark_triangle, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Error', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            viewModel.errorMessage!,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () {
              if (viewModel.capturedPhoto != null) {
                viewModel.clearErrorMessage();
              } else {
                viewModel.clearCapturedPhoto();
              }
            },
            child: Text('Dismiss', style: TextStyle(color: appColors.errorColor, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  /// Gallery and Capture buttons in a Row (pre-capture).
  Widget _buildGalleryCaptureButtonsRow(BuildContext context, CaptureViewModel viewModel) {
    final isPhotoUploadAllowed = !_isFlashbackMultiShot &&
        !_isFlashbackSingleShot &&
        context.select<AppSettingsManager, bool>(
          (settingsManager) =>
              settingsManager.settings?.photoUploadAllowed == true,
        );
    final flashback = _isFlashbackMultiShot || _isFlashbackSingleShot;
    final countdownSecs = captureCountdownSecondsForMode(
      isFlashbackMultiShot: flashback,
    );

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isPhotoUploadAllowed) ...[
            ElevatedButton.icon(
              style: captureScreenButtonStyle(secondary: true),
              onPressed:
                  (viewModel.isCapturing ||
                          viewModel.isSelectingFromGallery ||
                          viewModel.isWaitingForPhoneUpload)
                      ? null
                      : () async => _handleSelectFromGallery(viewModel),
              icon: const Icon(CupertinoIcons.photo, size: 20),
              label: Text(
                viewModel.isSelectingFromGallery
                    ? 'Selecting…'
                    : AppStrings.galleryButtonLabel,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: captureScreenButtonStyle(secondary: true),
              onPressed:
                  (viewModel.isCapturing ||
                          viewModel.isSelectingFromGallery ||
                          viewModel.isWaitingForPhoneUpload)
                      ? null
                      : () async {
                          await showPhoneUploadQrSheet(
                            context: context,
                            viewModel: viewModel,
                          );
                        },
              icon: const Icon(CupertinoIcons.qrcode, size: 20),
              label: Text(
                viewModel.isWaitingForPhoneUpload
                    ? AppStrings.phoneUploadWaiting
                    : AppStrings.phoneUploadButtonLabel,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (flashback &&
              _stripShots.isNotEmpty &&
              ClassicStripScrubCoordinator.instance.shotCount > 0) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ClassicScrubProgressDots(
                statuses: ClassicStripScrubCoordinator.instance.statuses,
                totalSlots: _multiShotTotal,
              ),
            ),
            ElevatedButton(
              style: captureScreenButtonStyle(secondary: true),
              onPressed: (viewModel.isCapturing ||
                      _uvcCaptureInFlight ||
                      _stripFinishing)
                  ? null
                  : () => unawaited(_retakeLastFlashbackShot()),
              child: const Text(AppStrings.flashbackRetakeLast),
            ),
            const SizedBox(height: 12),
          ],
          ElevatedButton.icon(
            style: captureScreenButtonStyle(),
            onPressed: (viewModel.isCapturing ||
                    _uvcCaptureInFlight ||
                    viewModel.isSelectingFromGallery ||
                    viewModel.isCountingDown ||
                    _flashbackCountdownStarting ||
                    (_isFlashbackSingleShot &&
                        !classicOneShotMayStartCountdown(_oneShotPhase)) ||
                    (_isUsingUvc && !_uvcReadyForCapture))
                ? null
                : () async {
                    if (_isFlashbackSingleShot) {
                      _oneShotRequestGuestCapture();
                      return;
                    }
                    if (_isFlashbackMultiShot) {
                      await _startFlashbackAutoCountdown();
                      return;
                    }
                    if (_isUsingUvc) {
                      _fotoZenCaptureLocked = true;
                      await viewModel.captureWithCountdown(
                        () => _captureUvc(viewModel, source: 'ui_button'),
                        canStart: () =>
                            _uvcReadyForCapture &&
                            !_uvcCaptureInFlight &&
                            _flashbackCameraReady &&
                            viewModel.capturedPhoto == null,
                        countdownSeconds: countdownSecs,
                        onCountdownFinished: _armUvcHdmiStillMask,
                      );
                    } else {
                      _fotoZenCaptureLocked = true;
                      await viewModel.capturePhotoWithCountdown(
                        countdownSeconds: countdownSecs,
                      );
                    }
                  },
            icon: const Icon(CupertinoIcons.camera, size: 20),
            label: Text(
              (viewModel.isCapturing ||
                      _uvcCaptureInFlight ||
                      _uvcHdmiStillMaskArmed)
                  ? AppStrings.captureCapturingPhoto
                  : (flashback
                      ? AppStrings.flashbackTakeShot
                      : 'Capture'),
            ),
          ),
        ],
      ),
    );
  }
}
