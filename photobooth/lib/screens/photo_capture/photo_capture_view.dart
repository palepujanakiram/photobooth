import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:camera_native_details/camera_native_details.dart';
import 'package:uvccamera/uvccamera.dart';
import 'photo_capture_camera_picker_screen.dart';
import 'photo_capture_preview_rotation.dart';
import 'photo_capture_view_aspect.dart';
import 'photo_capture_view_handlers.dart';
import 'photo_capture_view_layout.dart';
import 'photo_capture_view_scaffold.dart';
import 'photo_capture_viewmodel.dart';
import 'photo_image_from_xfile_io.dart' if (dart.library.html) 'photo_image_from_xfile_web.dart' as photo_image;
import '../../utils/app_runtime_config.dart';
import '../../utils/constants.dart';
import '../../utils/device_classifier.dart';
import '../../utils/logger.dart';
import '../../utils/uvc_capture_config.dart';
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
  UvcCameraDevice? _uvcDevice;
  UvcCameraController? _uvcController;
  bool _uvcInitializing = false;
  String? _uvcError;
  bool _showCaptureFlash = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _captureViewModel = CaptureViewModel();

    _hardwareKeySub?.cancel();
    _hardwareKeySub = HardwareKeyService.events.listen((e) async {
      // Volume up/down from Bluetooth clickers usually maps to these.
      if (!e.isActionDown) return;
      if (e.keyCode != 24 && e.keyCode != 25) return;
      // Don't interrupt after a photo is already captured.
      if (_captureViewModel.capturedPhoto != null) return;
      await _captureViewModel.capturePhotoWithCountdown();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await HardwareKeyService.setEnabled(true);
      _hardwareKeysEnabled = true;
      // Await prefs before camera so SharedPreferences I/O does not overlap native
      // camera enumeration / CameraController.initialize (reduces peak contention on 2 GB devices).
      await _captureViewModel.loadPreviewRotation();
      if (!mounted) return;
      await _resetAndInitializeCameras();
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
    // Run after camera: device_info + MediaQuery — avoids overlapping with
    // availableCameras() / initialize() native heap spike.
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hardwareKeySub?.cancel();
    _hardwareKeySub = null;
    if (_hardwareKeysEnabled) {
      HardwareKeyService.setEnabled(false);
    }
    unawaited(_disposeUvc());
    _captureViewModel.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // On some Android tablets, orientation changes don't reliably update camera preview
    // unless we refresh rotation metadata. Keep this lightweight.
    _captureViewModel.refreshDisplayRotation();
  }

  Future<void> _disposeUvcController() async {
    final ctrl = _uvcController;
    _uvcController = null;
    _uvcInitializing = false;
    if (ctrl != null) {
      try {
        await ctrl.dispose();
      } catch (_) {
        // Best-effort.
      }
    }
  }

  Future<void> _disposeUvc() async {
    await _disposeUvcController();
    _uvcDevice = null;
    _uvcError = null;
  }

  bool get _isUsingUvc => _uvcDevice != null;

  Future<void> _initUvc(UvcCameraDevice device) async {
    setState(() {
      _uvcDevice = device;
      _uvcInitializing = true;
      _uvcError = null;
    });

    // Stop built-in camera to avoid native buffer overlap.
    _captureViewModel.disposeCamera();

    try {
      final ok = await UvcCamera.requestDevicePermission(device);
      if (!ok) {
        if (!mounted) return;
        setState(() {
          _uvcInitializing = false;
          _uvcError = 'USB camera permission was not granted.';
        });
        return;
      }
      final ctrl = UvcCameraController(
        device: device,
        resolutionPreset: UvcCaptureConfig.resolutionPreset,
      );
      await ctrl.initialize();
      if (!mounted) return;
      await _captureViewModel.refreshDisplayRotation();
      if (!mounted) return;
      setState(() {
        _uvcController = ctrl;
        _uvcInitializing = false;
        _uvcError = null;
      });
    } catch (e) {
      AppLogger.error('UVC init failed (main preview)', error: e);
      if (!mounted) return;
      setState(() {
        _uvcInitializing = false;
        _uvcError = 'Failed to initialize USB camera: $e';
      });
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
      await _initUvc(picked);
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

  Widget _buildUvcPreview(BuildContext context, CaptureViewModel viewModel) {
    final ctrl = _uvcController;
    if (_uvcInitializing) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_uvcError != null) {
      return Container(
        color: AppColors.of(context).backgroundColor,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _uvcError!,
              style: TextStyle(color: AppColors.of(context).textColor),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    if (ctrl == null || !ctrl.value.isInitialized) {
      return Container(
        color: AppColors.of(context).backgroundColor,
        child: Center(
          child: Text(
            'USB camera preview not available',
            style: TextStyle(color: AppColors.of(context).textColor),
          ),
        ),
      );
    }

    final previewMode = ctrl.value.previewMode;
    final frameWidth = previewMode?.frameWidth.toDouble() ?? 1.0;
    final frameHeight = previewMode?.frameHeight.toDouble() ?? 1.0;
    final baseAspect = frameWidth / frameHeight;
    final effectiveTurns = viewModel.uvcPreviewEffectiveQuarterTurns;

    return buildRotatedCoverPreview(
      preview: ctrl.buildPreview(),
      effectiveQuarterTurns: effectiveTurns,
      baseAspectRatio: baseAspect <= 0 ? 1.0 : baseAspect,
      frameSize: Size(frameWidth, frameHeight),
    );
  }

  Future<void> _captureUvc(CaptureViewModel viewModel) async {
    final ctrl = _uvcController;
    final device = _uvcDevice;
    if (ctrl == null || device == null || viewModel.isCapturing) return;
    final cameraId = 'uvc:${device.vendorId}:${device.productId}:${device.name}';
    try {
      if (mounted) setState(() => _showCaptureFlash = true);
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
      final file = await ctrl.takePicture();
      // Release USB preview buffers before decode/resize/encode on the UI isolate.
      await _disposeUvcController();
      if (mounted) setState(() {});
      await viewModel.setCapturedPhotoFromExternalFile(
        rawFile: file,
        cameraId: cameraId,
      );
    } catch (e, st) {
      AppLogger.error('UVC takePicture failed (main preview)', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _uvcError = 'USB camera capture failed: $e';
      });
    } finally {
      if (mounted) setState(() => _showCaptureFlash = false);
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
    final uvcReady = _isUsingUvc &&
        _uvcController != null &&
        _uvcController!.value.isInitialized;
    if (!uvcReady && !viewModel.isReady && viewModel.capturedPhoto == null) {
      return const Center(
        child: Text(
          'Camera not ready',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    final previewWidget = _isUsingUvc
        ? _buildUvcPreview(context, viewModel)
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
              return PhotoCaptureScaffold(
                viewModel: viewModel,
                onBack: () => Navigator.pop(context),
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
                  if (!hasCapturedPhoto && AppConstants.kShowNativeCameraInfoPane)
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
                  if (_showCaptureFlash ||
                      (viewModel.isCapturing && !hasCapturedPhoto))
                    Positioned.fill(
                      child: ColoredBox(
                        color: _showCaptureFlash
                            ? Colors.white
                            : Colors.black.withValues(alpha: 0.35),
                        child: viewModel.isCapturing && !_showCaptureFlash
                            ? const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                ),
                              )
                            : null,
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

  /// Builds the countdown overlay (3, 2, 1)
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
            onPressed: () async {
              await handleCapturedPhotoRetake(
                context: context,
                viewModel: viewModel,
                isMounted: () => mounted,
              );
              final device = _uvcDevice;
              if (mounted && device != null && _uvcController == null) {
                await _initUvc(device);
              }
            },
            child: const Text('Retake'),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            style: captureScreenButtonStyle(),
            onPressed: viewModel.canContinueUpload
                ? () => handleCapturedPhotoContinue(
                      context: context,
                      viewModel: viewModel,
                      isMounted: () => mounted,
                    )
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
                      : () async => await viewModel.selectFromGallery(),
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
                : () async {
                    if (_isUsingUvc) {
                      await _captureUvc(viewModel);
                    } else {
                      await viewModel.capturePhotoWithCountdown();
                    }
                  },
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
