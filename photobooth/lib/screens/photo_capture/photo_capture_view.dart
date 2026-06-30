import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:camera_native_details/camera_native_details.dart';
import 'photo_capture_camera_picker_screen.dart';
import 'photo_capture_preview_rotation.dart';
import 'photo_capture_view_aspect.dart';
import 'photo_capture_view_handlers.dart';
import 'photo_capture_exit_handlers.dart';
import 'photo_capture_gallery_handlers.dart';
import 'photo_capture_idle_policy.dart';
import 'photo_capture_view_layout.dart';
import 'photo_capture_view_scaffold.dart';
import 'photo_capture_viewmodel.dart';
import 'photo_model.dart';
import 'photo_image_from_xfile_io.dart' if (dart.library.html) 'photo_image_from_xfile_web.dart' as photo_image;
import '../../utils/app_runtime_config.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../utils/device_classifier.dart';
import '../../utils/logger.dart';
import '../../services/app_settings_manager.dart';
import '../../services/error_reporting/error_reporting_manager.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/centered_max_width.dart';
import 'photo_capture_rotation_screen.dart';
import '../../services/hardware_key_service.dart';

class PhotoCaptureScreen extends StatefulWidget {
  const PhotoCaptureScreen({super.key});

  @override
  State<PhotoCaptureScreen> createState() => _PhotoCaptureScreenState();
}

class _PhotoCaptureScreenState extends State<PhotoCaptureScreen>
    with WidgetsBindingObserver {
  late CaptureViewModel _captureViewModel;
  StreamSubscription<HardwareKeyEvent>? _hardwareKeySub;
  bool _hardwareKeysEnabled = false;
  bool _prefillApplied = false;
  Timer? _poseIdleTimer;
  bool _navigatingAwayFromCapture = false;
  bool _appInForeground = true;

  CaptureScreenIdleInput _poseIdleInput(CaptureViewModel viewModel) {
    return CaptureScreenIdleInput(
      isNavigatingAway: _navigatingAwayFromCapture,
      isCapturing: viewModel.isCapturing,
      isUploading: viewModel.isUploading,
      isCountingDown: viewModel.isCountingDown,
      appInForeground: _appInForeground,
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
  }

  Future<void> _releaseCaptureHardware() async {
    _stopPoseIdleTimer();
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefillApplied) return;
    _prefillApplied = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['photo'] is PhotoModel) {
      final photo = args['photo'] as PhotoModel;
      _captureViewModel.capturedPhoto = photo;
    }
  }

  void _safeUnawaited(Future<void> future, {required String label}) {
    unawaited(
      future.catchError((Object e, StackTrace st) {
        AppLogger.error(label, error: e, stackTrace: st);
      }),
    );
  }

  bool _isHardwareShutterKey(int keyCode) {
    const codes = <int>{
      24, // volume up
      25, // volume down
      27, // camera
      80, // focus
      66, // enter
      23, // dpad center
      62, // space
    };
    return codes.contains(keyCode);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _captureViewModel = CaptureViewModel();
    _captureViewModel.addListener(_onCaptureViewModelStateChanged);

    _hardwareKeySub?.cancel();
    _hardwareKeySub = HardwareKeyService.events.listen((e) async {
      if (!e.isActionDown) return;
      _notePoseUserActivity();
      if (_captureViewModel.capturedPhoto != null) return;
      if (!_isHardwareShutterKey(e.keyCode)) return;
      await _captureViewModel.capturePhotoWithCountdown();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await HardwareKeyService.setEnabled(true);
      _hardwareKeysEnabled = true;
      await _captureViewModel.loadPreviewRotation();
      if (!mounted) return;
      await _resetAndInitializeCameras();
      if (!mounted) return;
      _syncPoseIdleTimer(_captureViewModel);
    });
  }

  /// Common function to reset and initialize cameras
  /// Used both when entering the screen and when tapping the reload button
  /// Uses sync tablet check so cameras load immediately; does not block on slow getDeviceType().
  Future<void> _resetAndInitializeCameras({bool forceRefresh = false}) async {
    if (!mounted) return;

    _captureViewModel.setDeviceType(null);
    await _captureViewModel.resetAndInitializeCameras(
      forceRefresh: forceRefresh,
    );
    if (!mounted) return;
    try {
      final deviceType = await DeviceClassifier.getDeviceType(context);
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
    await _reportCaptureScreenNoCameraIfNeeded();
  }

  Future<void> _reportCaptureScreenNoCameraIfNeeded() async {
    if (!mounted) return;
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
    _stopPoseIdleTimer();
    _hardwareKeySub?.cancel();
    _hardwareKeySub = null;
    if (_hardwareKeysEnabled) {
      HardwareKeyService.setEnabled(false);
    }
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
  }

  @override
  void didChangeMetrics() {
    _captureViewModel.refreshDisplayRotation();
  }

  Future<void> _handleSelectFromGallery(CaptureViewModel viewModel) async {
    await pauseCapturePreviewForGallery(
      disposeCamera: _captureViewModel.disposeCamera,
    );
    if (!mounted) return;
    setState(() {});

    try {
      await viewModel.selectFromGallery();
    } finally {
      if (mounted) {
        final accepted = viewModel.capturedPhoto != null;
        await finalizeGallerySelection(
          photoAccepted: accepted,
          disposeCamera: _captureViewModel.disposeCamera,
        );
        if (!accepted) {
          await resumeCapturePreviewAfterGallery(
            hasCapturedPhoto: viewModel.capturedPhoto != null,
            resumeBuiltInPreview: _captureViewModel.resumeLivePreviewAfterRetake,
          );
        }
        setState(() {});
      }
    }
  }

  Future<void> _handleRetake(BuildContext context) async {
    await handleCapturedPhotoRetake(
      context: context,
      viewModel: _captureViewModel,
      isMounted: () => mounted,
    );
    if (!mounted) return;
    await _captureViewModel.resumeLivePreviewAfterRetake();
  }

  Future<void> _handleCaptureBack(BuildContext context) async {
    _notePoseUserActivity();
    if (_captureViewModel.capturedPhoto != null) {
      await _handleRetake(context);
      return;
    }
    await _exitCaptureToTerms(
      sessionEndContext: 'capture_back',
      endCustomerSession: false,
    );
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
      await viewModel.switchCamera(picked);
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

  Widget _buildNoCamerasYetState(BuildContext context) {
    final allowGallery = context.select<AppSettingsManager, bool>(
      (m) => m.settings?.photoUploadAllowed == true,
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(
              allowGallery
                  ? 'Waiting for camera… or use Gallery below if this takes too long.'
                  : 'Waiting for camera…',
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
          ],
        ),
      ),
    );
  }

  Widget _buildDetectingCamerasState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 20),
          Text(
            'Detecting cameras…',
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
    return Center(
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
                onPressed: () => _resetAndInitializeCameras(forceRefresh: true),
                child: const Text('Retry'),
              ),
              TextButton(
                onPressed: () => openAppSettings(),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureBodyContent(
    BuildContext context,
    CaptureViewModel viewModel,
  ) {
    if (viewModel.isLoadingCameras) return _buildDetectingCamerasState();
    if (viewModel.isInitializing) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (viewModel.availableCameras.isEmpty && !viewModel.hasError) {
      return _buildNoCamerasYetState(context);
    }
    if (viewModel.hasError && viewModel.capturedPhoto == null) {
      return _buildCaptureFatalErrorState(context, viewModel);
    }
    if (!viewModel.isSelectingFromGallery &&
        !viewModel.isReady &&
        viewModel.capturedPhoto == null) {
      return const Center(
        child: Text(
          'Camera not ready',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    final previewWidget = viewModel.isSelectingFromGallery
        ? buildGallerySelectionPlaceholder()
        : _buildCameraPreviewWithRotation(context, viewModel);
    final hasCapturedPhoto = viewModel.capturedPhoto != null;
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12),
      child: _buildCaptureColumn(
        context: context,
        viewModel: viewModel,
        hasCapturedPhoto: hasCapturedPhoto,
        previewWidget: previewWidget,
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
    final showNativeDetails = AppConstants.kShowNativeCameraInfoPane &&
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
                              // Match live preview: full-bleed cover (no black “stencil”), smooth shutter transition.
                              fit: BoxFit.cover,
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
viewModel.previewSize != null)
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
                  if (!hasCapturedPhoto && viewModel.isCapturing)
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

    final preview = _buildPlatformPreview(controller);
    final effectiveQuarterTurns =
        (viewModel.previewAutoQuarterTurns +
                (viewModel.previewRotationDegrees ~/ 90) % 4) %
            4;
    final baseAspectRatio = controller.value.aspectRatio;

    return buildRotatedCoverPreview(
      preview: preview,
      effectiveQuarterTurns: effectiveQuarterTurns,
      baseAspectRatio: baseAspectRatio,
      frameSize: controller.value.previewSize,
    );
  }

  Widget _buildPlatformPreview(CameraController controller) {
    return CameraPreview(controller);
  }

  String _effectiveRotationLabel(CaptureViewModel viewModel) {
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
    return Container(
      color: Colors.black.withValues(alpha: 0.5),
      child: Center(
        child: Container(
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
      ),
    );
  }

  /// Retake and Continue buttons in a Row (post-capture).
  Widget _buildCapturedPhotoControlsRow(BuildContext context, CaptureViewModel viewModel) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton(
            style: captureScreenButtonStyle(secondary: true),
            onPressed: () => unawaited(_handleRetake(context)),
            child: const Text('Retake'),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            style: captureScreenButtonStyle(),
            onPressed: viewModel.canContinueUpload
                ? () async {
                    _navigatingAwayFromCapture = true;
                    _stopPoseIdleTimer();
                    await handleCapturedPhotoContinue(
                      context: context,
                      viewModel: viewModel,
                      isMounted: () => mounted,
                      releaseCaptureHardware: _releaseCaptureHardware,
                    );
                  }
                : null,
            child: viewModel.isUploading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    viewModel.isPreparingUploadPayload
                        ? 'Preparing…'
                        : 'Continue',
                  ),
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
    final isPhotoUploadAllowed = context.select<AppSettingsManager, bool>(
      (settingsManager) => settingsManager.settings?.photoUploadAllowed == true,
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
                  (viewModel.isCapturing || viewModel.isSelectingFromGallery)
                      ? null
                      : () async => _handleSelectFromGallery(viewModel),
              icon: viewModel.isSelectingFromGallery
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(CupertinoIcons.photo, size: 20),
              label: const Text('Gallery'),
            ),
            const SizedBox(height: 12),
          ],
          ElevatedButton.icon(
            style: captureScreenButtonStyle(),
            onPressed: (viewModel.isCapturing ||
                    viewModel.isSelectingFromGallery ||
                    viewModel.isCountingDown)
                ? null
: () async => viewModel.capturePhotoWithCountdown(),
            icon: viewModel.isCapturing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(CupertinoIcons.camera, size: 20),
            label: const Text('Capture'),
          ),
        ],
      ),
    );
  }
}
