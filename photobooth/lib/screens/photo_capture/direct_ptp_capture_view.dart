import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme_selection/theme_model.dart';
import '../../services/app_settings_manager.dart';
import '../../services/direct_ptp_camera_service.dart';
import '../../utils/app_strings.dart';
import '../../utils/capture_session_kind.dart';
import '../../utils/classic_shot_mode.dart';
import '../../utils/constants.dart';
import '../../utils/image_helper.dart';
import '../../utils/kiosk_page_route.dart';
import '../../utils/logger.dart';
import '../../utils/route_args.dart';
import '../../views/widgets/theme_background.dart';
import '../fotoflashback/fotoflashback_filter_view.dart';
import 'direct_ptp_capture_helpers.dart';
import 'photo_capture_view_handlers.dart';
import 'photo_capture_viewmodel.dart';

/// POSE screen for the direct-PTP DSLR.
///
/// Runs in place of [PhotoCaptureScreen] when the camera source is
/// `direct_ptp`; both are registered behind the same route, so every existing
/// `pushNamed(kRouteCapture)` reaches whichever is configured.
///
/// This screen owns almost nothing: live view, the countdown, the shutter and
/// the multi-shot loop all live in the native `CanonCaptureActivity`, because
/// pushing ~20fps of frames through a platform channel is the cost the whole
/// direct-PTP design exists to avoid. What is left here is launching that
/// screen, and handing its results to exactly the same downstream flow the
/// Flutter capture screen uses — upload → theme selection for FotoZen, the look
/// picker for Classic.
class DirectPtpCaptureScreen extends StatefulWidget {
  const DirectPtpCaptureScreen({
    super.key,
    this.sessionKind = CaptureSessionKind.fotoZen,
    this.captureArgs,
    this.cameraService,
  });

  /// Immutable POSE flow — same contract as [PhotoCaptureScreen].
  final CaptureSessionKind sessionKind;

  final CaptureRouteArgs? captureArgs;

  /// Injected in tests; production builds the default bridge.
  final DirectPtpCameraService? cameraService;

  @override
  State<DirectPtpCaptureScreen> createState() => _DirectPtpCaptureScreenState();
}

class _DirectPtpCaptureScreenState extends State<DirectPtpCaptureScreen> {
  late final DirectPtpCameraService _camera =
      widget.cameraService ?? DirectPtpCameraService();

  late final CaptureViewModel _captureViewModel;

  /// What the screen is waiting on, so the label says something true.
  ///
  /// A single "Starting the camera…" spinner across capture, processing and
  /// upload made a working session indistinguishable from a hung one — which is
  /// exactly how the first hardware hang presented.
  _DirectPtpPhase _phase = _DirectPtpPhase.starting;

  bool _sessionRunning = false;
  String? _error;

  /// True when the still is safely captured and only the hand-off failed.
  ///
  /// Retrying should then continue with the photo already taken, not make the
  /// guest pose again for a shot that is sitting on disk.
  bool _canRetryContinue = false;

  @override
  void initState() {
    super.initState();
    _captureViewModel = CaptureViewModel(
      appSettingsManager: context.read<AppSettingsManager>(),
    );
    // After the first frame so this screen is painted behind the native one —
    // otherwise the guest sees a blank route flash as the Activity comes up.
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_runSession()));
  }

  @override
  void dispose() {
    _captureViewModel.dispose();
    super.dispose();
  }

  ThemeModel? get _flashbackTheme => widget.captureArgs?.flashbackTheme;

  Future<void> _runSession() async {
    if (_sessionRunning) return;
    setState(() {
      _sessionRunning = true;
      _error = null;
      _canRetryContinue = false;
      _phase = _DirectPtpPhase.starting;
    });

    final kind = widget.sessionKind;
    final result = await _camera.runCaptureSession(
      shotCount: clampDirectPtpShotCount(directPtpShotCountFor(kind)),
      countdownSeconds: directPtpCountdownSecondsFor(kind),
      betweenShotSeconds: directPtpBetweenShotSeconds,
      titleText: AppStrings.posePageTitle,
      subtitleText: directPtpSubtitleFor(kind),
      cancelText: AppStrings.cancel,
    );

    if (!mounted) return;
    AppLogger.info('Direct PTP capture returned $result');

    if (result.isCancelled) {
      _leaveCapture();
      return;
    }

    if (!directPtpResultIsUsable(result, kind)) {
      setState(() {
        _sessionRunning = false;
        _error = directPtpErrorMessage(
          result.errorCode,
          fallback: result.errorMessage,
        );
      });
      return;
    }

    await _handleShots(result);
  }

  Future<void> _handleShots(DirectPtpCaptureResult result) async {
    if (mounted) setState(() => _phase = _DirectPtpPhase.processing);

    // The display derivative, never the original: everything below this point
    // encodes and decodes the file, and a 6000x4000 JPEG is ~96MB as a bitmap.
    final files = result.shots
        .map((s) => XFile(s.previewPath, mimeType: 'image/jpeg'))
        .toList();

    if (widget.sessionKind.isClassic) {
      await _finishClassic(files);
    } else {
      await _finishFotoZen(files.first);
    }
  }

  Future<void> _finishFotoZen(XFile file) async {
    await _captureViewModel.adoptExternalCapture(file, cameraId: _cameraId);
    if (!mounted) return;
    await _continueWithCapturedPhoto();
  }

  /// Hands the still to the normal upload → theme-selection flow.
  ///
  /// [handleCapturedPhotoContinue] returns without navigating on several paths —
  /// upload failure, an already-in-flight upload, an unmounted context — because
  /// on the Flutter capture screen the guest is left looking at their photo with
  /// a Continue button and can simply tap again. This screen has no such UI, so
  /// a silent return used to leave it spinning forever with the photo already
  /// safely on disk.
  ///
  /// Still being mounted afterwards *is* the signal that it did not navigate:
  /// success replaces this route, which disposes us.
  Future<void> _continueWithCapturedPhoto() async {
    setState(() => _phase = _DirectPtpPhase.processing);
    // Logged because the handler's early returns are silent, and which one fired
    // is the difference between "no kiosk session", "upload already running" and
    // "upload rejected" — three different fixes.
    AppLogger.info(
      '[PTP_CONTINUE] begin canContinue=${_captureViewModel.canContinueUpload} '
      'isUploading=${_captureViewModel.isUploading} '
      'hasPhoto=${_captureViewModel.capturedPhoto != null}',
    );
    await handleCapturedPhotoContinue(
      context: context,
      viewModel: _captureViewModel,
      isMounted: () => mounted,
    );
    if (!mounted) return;
    AppLogger.warning(
      '[PTP_CONTINUE] did not navigate — '
      'hasPhoto=${_captureViewModel.capturedPhoto != null} '
      'hasError=${_captureViewModel.hasError} error=${_captureViewModel.errorMessage}',
    );
    setState(() {
      _sessionRunning = false;
      _canRetryContinue = true;
      _error = _captureViewModel.errorMessage?.trim().isNotEmpty == true
          ? _captureViewModel.errorMessage
          : AppStrings.directPtpContinueFailed;
    });
  }

  /// Retries the hand-off with the photo already taken.
  Future<void> _retryContinue() async {
    if (_captureViewModel.capturedPhoto == null) {
      // Nothing to continue with; fall back to reopening the camera.
      await _runSession();
      return;
    }
    setState(() {
      _sessionRunning = true;
      _error = null;
    });
    await _continueWithCapturedPhoto();
  }

  /// Discards the captured still and reopens the native camera screen.
  Future<void> _retake() async {
    await _captureViewModel.clearCapturedPhotoAwaitingSession();
    if (!mounted) return;
    setState(() => _canRetryContinue = false);
    await _runSession();
  }

  Future<void> _finishClassic(List<XFile> files) async {
    final theme = _flashbackTheme;
    if (theme == null) {
      AppLogger.error('Classic direct-PTP finish missing flashbackTheme');
      setState(() {
        _sessionRunning = false;
        _error = AppStrings.flashbackFinishEncodeFailed;
      });
      return;
    }

    final dataUrls = <String>[];
    for (final file in files) {
      dataUrls.add(await ImageHelper.encodeImageToBase64(file));
    }
    if (!mounted) return;

    if (dataUrls.any((u) => u.trim().isEmpty)) {
      setState(() {
        _sessionRunning = false;
        _error = AppStrings.flashbackFinishEncodeFailed;
      });
      return;
    }

    final mode = widget.sessionKind.isClassicFourShot
        ? ClassicShotMode.fourShot
        : ClassicShotMode.single6x4;
    final filterArgs = FlashbackFilterArgs(
      theme: theme,
      imageDataUrls: dataUrls,
      // The look screen adopts any in-flight Gemini polish; claiming it is done
      // here would skip cleanup that never ran.
      overlayCleanupAlreadyDone: false,
      shotCleaned: List<bool>.filled(dataUrls.length, false),
      classicShotMode: mode,
    );

    // Direct page route, not a named one: named `routes:` entries build a const
    // screen and drop typed args on Android TV, which strands the look picker.
    await pushReplacementKioskFade<void, void>(
      context,
      FotoFlashbackFilterScreen(filterArgs: filterArgs),
      settings: RouteSettings(
        name: AppConstants.kRouteFlashbackFilter,
        arguments: filterArgs,
      ),
    );

    // Same reasoning as the FotoZen path: a successful push replaces this route
    // and disposes us, so still being mounted means the hand-off did not happen.
    // Without this the strip is encoded, on disk, and the screen spins forever.
    if (!mounted) return;
    setState(() {
      _sessionRunning = false;
      _error = AppStrings.flashbackFinishEncodeFailed;
    });
  }

  String get _cameraId => 'ptp:${AppStrings.directPtpCameraLabel}';

  void _leaveCapture() {
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      unawaited(
        Navigator.of(context).pushReplacementNamed(AppConstants.kRouteSplash),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _captureViewModel,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(child: ThemeBackground(theme: null)),
            SafeArea(child: Center(child: _buildBody())),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final error = _error;
    if (error != null) return _buildError(error);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(color: Colors.white),
        const SizedBox(height: 20),
        Text(
          _phase.label,
          style: const TextStyle(color: Colors.white, fontSize: 18),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildError(String error) {
    // When the photo already exists, the primary action continues with it.
    // Offering "Try again" there would make the guest pose a second time for a
    // shot that is sitting on disk.
    final primaryLabel = _canRetryContinue
        ? AppStrings.directPtpContinue
        : AppStrings.directPtpRetry;
    final primaryAction =
        _canRetryContinue ? _retryContinue : _runSession;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.photo_camera_outlined,
              color: Colors.white70, size: 56),
          const SizedBox(height: 16),
          Text(
            error,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () => unawaited(primaryAction()),
                child: Text(primaryLabel),
              ),
              if (_canRetryContinue)
                OutlinedButton(
                  onPressed: () => unawaited(_retake()),
                  child: const Text(
                    AppStrings.directPtpRetake,
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              TextButton(
                onPressed: _leaveCapture,
                child: const Text(
                  AppStrings.cancel,
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// What the screen is waiting on.
enum _DirectPtpPhase {
  /// The native capture screen is coming up and owns the display.
  starting,

  /// Shots are back; building derivatives, encoding and uploading.
  processing;

  String get label => switch (this) {
        _DirectPtpPhase.starting => AppStrings.directPtpStartingCamera,
        _DirectPtpPhase.processing => AppStrings.directPtpProcessing,
      };
}
