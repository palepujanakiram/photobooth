import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:camera_native_details/camera_native_details.dart';
import 'photo_capture_viewmodel.dart';
import 'photo_image_from_xfile_io.dart' if (dart.library.html) 'photo_image_from_xfile_web.dart' as photo_image;
import '../../utils/app_runtime_config.dart';
import '../../utils/constants.dart';
import '../../utils/device_classifier.dart';
import '../../services/app_settings_manager.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/full_screen_loader.dart';
import '../../views/widgets/theme_background.dart';
import '../../views/widgets/debug_ram_monitor_overlay.dart';
import '../../views/widgets/leading_with_alice.dart';
import 'photo_capture_rotation_screen.dart';
import '../../services/hardware_key_service.dart';
import '../../utils/route_args.dart';

class PhotoCaptureScreen extends StatefulWidget {
  const PhotoCaptureScreen({super.key});

  @override
  State<PhotoCaptureScreen> createState() => _PhotoCaptureScreenState();
}

class _PhotoCaptureScreenState extends State<PhotoCaptureScreen> {
  late CaptureViewModel _captureViewModel;
  StreamSubscription<HardwareKeyEvent>? _hardwareKeySub;

  @override
  void initState() {
    super.initState();
    _captureViewModel = CaptureViewModel();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await HardwareKeyService.setEnabled(true);
      _hardwareKeySub?.cancel();
      _hardwareKeySub = HardwareKeyService.events.listen((e) async {
        // Volume up/down from Bluetooth clickers usually maps to these.
        if (!e.isActionDown) return;
        if (e.keyCode != 24 && e.keyCode != 25) return;
        // Don't interrupt after a photo is already captured.
        if (_captureViewModel.capturedPhoto != null) return;
        await _captureViewModel.capturePhotoWithCountdown();
      });
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
    } catch (_) {}
  }

  @override
  void dispose() {
    HardwareKeyService.setEnabled(false);
    _hardwareKeySub?.cancel();
    _captureViewModel.dispose();
    super.dispose();
  }

  void _showCameraSelectionDialog(BuildContext context, CaptureViewModel viewModel) {
    final uniqueCameras = _getUniqueCameras(viewModel.availableCameras, viewModel);
    if (uniqueCameras.isEmpty) return;

    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (pickerContext) => Scaffold(
          appBar: AppBar(
            centerTitle: true,
            title: const Text('Select Camera'),
            leading: IconButton(
              icon: const Icon(CupertinoIcons.xmark),
              onPressed: () => Navigator.pop(pickerContext),
            ),
          ),
          body: SafeArea(
            child: ListView.builder(
              itemCount: uniqueCameras.length,
              itemBuilder: (_, index) {
                final camera = uniqueCameras[index];
                final isActive = viewModel.currentCamera?.name == camera.name;
                final displayName = viewModel.getCameraDisplayName(camera);
                return ListTile(
                  title: Text(displayName),
                  leading: isActive
                      ? const Icon(CupertinoIcons.checkmark_circle_fill, color: Colors.blue)
                      : null,
                  onTap: () {
                    Navigator.pop(pickerContext);
                    if (!isActive) viewModel.switchCamera(camera);
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _captureViewModel,
      child: Consumer<CaptureViewModel>(
        builder: (context, viewModel, child) {
          return ListenableBuilder(
            listenable: AppRuntimeConfig.instance,
            builder: (context, _) {
              return Scaffold(
                backgroundColor: Colors.transparent,
                extendBodyBehindAppBar: true,
                appBar: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  surfaceTintColor: Colors.transparent,
                  forceMaterialTransparency: true,
                  centerTitle: true,
                  systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
                    statusBarColor: Colors.transparent,
                    systemNavigationBarColor: Colors.transparent,
                  ),
                  title: const Text(
                    'Capture Photo',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 17,
                    ),
                  ),
                  leading: IconButton(
                    icon: const Icon(CupertinoIcons.back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  actions: [
                    if (viewModel.availableCameras.length > 1)
                      IconButton(
                        icon: Icon(
                          CupertinoIcons.camera_rotate,
                          color: (viewModel.isLoadingCameras || viewModel.isInitializing)
                              ? Colors.grey
                              : Colors.white,
                        ),
                        onPressed: viewModel.isLoadingCameras || viewModel.isInitializing
                            ? null
                            : () => _showCameraSelectionDialog(context, viewModel),
                      ),
                    IconButton(
                      icon: Icon(
                        CupertinoIcons.rotate_right,
                        color: (viewModel.isLoadingCameras || viewModel.isInitializing)
                            ? Colors.grey
                            : Colors.white,
                      ),
                      onPressed: viewModel.isLoadingCameras || viewModel.isInitializing
                          ? null
                          : () => _openPreviewRotationScreen(context, viewModel),
                    ),
                    IconButton(
                      icon: Icon(
                        CupertinoIcons.arrow_clockwise,
                        color: (viewModel.isLoadingCameras || viewModel.isInitializing)
                            ? Colors.grey
                            : Colors.white,
                      ),
                      onPressed: viewModel.isLoadingCameras || viewModel.isInitializing
                          ? null
                          : () => _resetAndInitializeCameras(forceRefresh: true),
                    ),
                    const AppBarAliceAction(),
                  ],
                ),
                body: Stack(
                  fit: StackFit.expand,
                  children: [
                    const Positioned.fill(
                      child: ThemeBackground(theme: null),
                    ),
                    SafeArea(
                      top: false,
                      bottom: false,
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: MediaQuery.paddingOf(context).top + kToolbarHeight,
                        ),
                        child: Builder(
                          builder: (context) {
                            final viewModel =
                                Provider.of<CaptureViewModel>(context, listen: true);
                            // "Detecting cameras…" full-screen state like fluttercamerabasic (loading gate)
                            if (viewModel.isLoadingCameras) {
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
                            if (viewModel.isInitializing) {
                              return const Center(
                                child: CircularProgressIndicator(color: Colors.white),
                              );
                            }
                            if (viewModel.availableCameras.isEmpty && !viewModel.hasError) {
                              return const Center(
                                child: CircularProgressIndicator(color: Colors.white),
                              );
                            }

                            if (viewModel.hasError) {
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
                                      style: const TextStyle(
                                        fontSize: 16,
                                        color: Colors.white,
                                      ),
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
                                  ],
                                ),
                              );
                            }

                            if (!viewModel.isReady) {
                              return const Center(
                                child: Text(
                                  'Camera not ready',
                                  style: TextStyle(color: Colors.white),
                                ),
                              );
                            }

                            final Widget previewWidget =
                                _buildCameraPreviewWithRotation(context, viewModel);
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
                          },
                        ),
                      ),
                    ),
                    if (viewModel.isUploading)
                      Positioned.fill(
                        child: FullScreenLoader(
                          text: 'Processing Your Photo',
                          loaderColor: Colors.blue,
                          elapsedSeconds: viewModel.uploadElapsedSeconds,
                        ),
                      ),
                    Consumer<AppSettingsManager>(
                      builder: (context, appSettings, _) {
                        if (appSettings.settings?.showGenerationCommentary != true) {
                          return const SizedBox.shrink();
                        }
                        return Positioned(
                          left: 10,
                          top: MediaQuery.paddingOf(context).top + kToolbarHeight + 6,
                          child: const DebugRamMonitorOverlay(),
                        );
                      },
                    ),
                  ],
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
        // 2. Buttons in a Row
        if (!hasCapturedPhoto) ...[
          _buildGalleryCaptureButtonsRow(context, viewModel),
          const SizedBox(height: 12),
        ] else ...[
          _buildCapturedPhotoControlsRow(context, viewModel),
          const SizedBox(height: 12),
        ],
        // 3. Preview or captured photo: same aspect as theme hero card; size capped so landscape matches carousel scale.
        Expanded(
          child: _buildCapturePreviewCard(
            context,
            viewModel,
            previewWidget,
            hasCapturedPhoto,
          ),
        ),
        if (!hasCapturedPhoto && viewModel.hasError && viewModel.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _buildCaptureErrorSection(context, viewModel),
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
        final aspect = _captureCardAspectRatio(
          context,
          viewModel,
          hasCapturedPhoto,
          fallbackAspect,
          constraints,
        );

        final widthCapFrac = isLandscape
            ? AppConstants.kCapturePreviewCardMaxWidthFractionLandscape
            : AppConstants.kCapturePreviewCardMaxWidthFractionPortrait;
        final heightCapFrac = isLandscape
            ? AppConstants.kCapturePreviewCardMaxHeightFractionLandscape
            : (isPhonePortrait
                ? AppConstants.kCapturePreviewCardMaxHeightFractionPhonePortrait
                : AppConstants.kCapturePreviewCardMaxHeightFractionPortrait);

        // Tablets: use the full canvas available for a cleaner kiosk-style preview.
        final maxW = isTablet
            ? constraints.maxWidth
            : math.min(constraints.maxWidth, media.width * widthCapFrac);
        final maxH = isTablet
            ? constraints.maxHeight
            : math.min(constraints.maxHeight, media.height * heightCapFrac);

        late double cardW;
        late double cardH;
        if (maxW / maxH > aspect) {
          cardH = maxH;
          cardW = cardH * aspect;
        } else {
          cardW = maxW;
          cardH = cardW / aspect;
        }

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
                    child: viewModel.capturedPhoto != null
                        ? photo_image.imageFromXFileSized(
                            viewModel.capturedPhoto!.imageFile,
                            cardW,
                            cardH,
                            // Use full canvas without distortion (crop instead of stretch).
                            fit: BoxFit.cover,
                          )
                        : previewWidget,
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
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Display size of the live preview after rotation (same math as the inner [SizedBox] below).
  Size? _livePreviewDisplaySize(CaptureViewModel viewModel) {
    final controller = viewModel.cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return null;
    }

    final previewSize = controller.value.previewSize;
    final baseAspectRatio = controller.value.aspectRatio;
    final autoQuarterTurns = _androidTvPreviewQuarterTurns(viewModel);
    final manualQuarterTurns = (viewModel.previewRotationDegrees ~/ 90) % 4;
    final effectiveQuarterTurns =
        (autoQuarterTurns + manualQuarterTurns) % 4;

    final displayAspectRatio =
        effectiveQuarterTurns.isOdd ? 1 / baseAspectRatio : baseAspectRatio;
    final width = previewSize == null
        ? (effectiveQuarterTurns.isOdd ? 1.0 : displayAspectRatio)
        : (effectiveQuarterTurns.isOdd
            ? previewSize.height
            : previewSize.width);
    final height = previewSize == null
        ? (effectiveQuarterTurns.isOdd ? displayAspectRatio : 1.0)
        : (effectiveQuarterTurns.isOdd
            ? previewSize.width
            : previewSize.height);

    if (width <= 0 || height <= 0) return null;
    return Size(width, height);
  }

  /// Width/height ratio for the capture card: decoded still, live preview, viewport slot on phones, or [fallbackAspect].
  ///
  /// On **phone portrait**, if the stream has not reported [CameraValue.previewSize] yet (common briefly on
  /// Android front cameras), the theme hero ratio (3:4.5) is a poor match — use [layoutConstraints] so
  /// the card tracks the Expanded preview area instead.
  double _captureCardAspectRatio(
    BuildContext context,
    CaptureViewModel viewModel,
    bool hasCapturedPhoto,
    double fallbackAspect,
    BoxConstraints layoutConstraints,
  ) {
    bool phonePortrait() {
      return MediaQuery.orientationOf(context) == Orientation.portrait &&
          MediaQuery.sizeOf(context).shortestSide < AppConstants.kTabletBreakpoint;
    }

    double viewportSlotAspect() {
      final w = layoutConstraints.maxWidth;
      final h = layoutConstraints.maxHeight;
      if (w <= 0 || h <= 0) return fallbackAspect;
      return (w / h).clamp(0.28, 0.92);
    }

    // Keep the capture card size consistent before/after capture by preferring the
    // live preview aspect ratio even after the still is taken. This avoids a
    // visible "jump" in placeholder size when switching from preview → still.
    if (hasCapturedPhoto) {
      final live = _livePreviewDisplaySize(viewModel);
      if (live != null && live.height > 0) {
        return (live.width / live.height).clamp(0.35, 2.85);
      }
      final pixels = viewModel.capturedImagePixelSize;
      if (pixels != null && pixels.height > 0) {
        return (pixels.width / pixels.height).clamp(0.35, 2.85);
      }
      if (phonePortrait()) return viewportSlotAspect();
      return fallbackAspect;
    }

    final controller = viewModel.cameraController;
    final previewSize = controller?.value.previewSize;
    final live = _livePreviewDisplaySize(viewModel);
    if (live != null && live.height > 0) {
      if (phonePortrait() && previewSize == null) {
        return viewportSlotAspect();
      }
      return (live.width / live.height).clamp(0.35, 2.85);
    }
    if (phonePortrait()) return viewportSlotAspect();
    return fallbackAspect;
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

    Widget preview = _buildPlatformPreview(controller);
    final autoQuarterTurns = _androidTvPreviewQuarterTurns(viewModel);
    final manualQuarterTurns = (viewModel.previewRotationDegrees ~/ 90) % 4;
    final effectiveQuarterTurns =
        (autoQuarterTurns + manualQuarterTurns) % 4;
    if (effectiveQuarterTurns != 0) {
      preview = RotatedBox(
        quarterTurns: effectiveQuarterTurns,
        child: preview,
      );
    }

    final displaySize = _livePreviewDisplaySize(viewModel);
    final baseAspectRatio = controller.value.aspectRatio;
    final displayAspectRatio =
        effectiveQuarterTurns.isOdd ? 1 / baseAspectRatio : baseAspectRatio;
    final width = displaySize?.width ??
        (effectiveQuarterTurns.isOdd ? 1.0 : displayAspectRatio);
    final height = displaySize?.height ??
        (effectiveQuarterTurns.isOdd ? displayAspectRatio : 1.0);

    // Always preserve aspect ratio and avoid stretching:
    // - Clip to the card bounds
    // - Use BoxFit.cover so the placeholder looks "full bleed" and premium
    //   (cropping is preferable to letterboxed tiny previews on tablets / landscape).
    return ClipRect(
      child: Center(
        child: FittedBox(
          fit: BoxFit.cover,
          alignment: Alignment.center,
          child: SizedBox(
            width: width,
            height: height,
            child: AspectRatio(
              aspectRatio: displayAspectRatio,
              child: preview,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlatformPreview(CameraController controller) {
    return CameraPreview(controller);
  }

  int _androidTvPreviewQuarterTurns(CaptureViewModel viewModel) {
    final camera = viewModel.currentCamera;
    if (camera == null) return 0;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return 0;
    if (!viewModel.shouldUseLandscapePreviewRotationWorkaround &&
        camera.lensDirection != CameraLensDirection.external) {
      return 0;
    }

    final surfaceRotationDegrees = switch (viewModel.displayRotation) {
      1 => 90,
      2 => 180,
      3 => 270,
      _ => 0,
    };

    final sensorOrientation = camera.sensorOrientation % 360;
    final rotationDegrees = switch (camera.lensDirection) {
      CameraLensDirection.front =>
        (sensorOrientation + surfaceRotationDegrees) % 360,
      _ => (sensorOrientation - surfaceRotationDegrees + 360) % 360,
    };

    return ((360 - rotationDegrees) % 360) ~/ 90;
  }

  String _effectiveRotationLabel(CaptureViewModel viewModel) {
    final autoTurns = _androidTvPreviewQuarterTurns(viewModel);
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

  /// Shared style for Capture Photo screen buttons (matches Generate Photo Continue button).
  static ButtonStyle _captureScreenButtonStyle({bool secondary = false}) {
    return ElevatedButton.styleFrom(
      backgroundColor: secondary ? Colors.grey : Colors.blue,
      foregroundColor: Colors.white,
      disabledBackgroundColor: Colors.grey.shade600,
      disabledForegroundColor: Colors.white70,
    );
  }

  /// Retake and Continue buttons in a Row (post-capture).
  Widget _buildCapturedPhotoControlsRow(BuildContext context, CaptureViewModel viewModel) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          style: _captureScreenButtonStyle(secondary: true),
          onPressed: () => viewModel.clearCapturedPhoto(),
          child: const Text('Retake'),
        ),
        const SizedBox(width: 12),
        ElevatedButton(
          style: _captureScreenButtonStyle(),
          onPressed: (viewModel.isCapturing || viewModel.isUploading)
              ? null
              : () async {
                  final currentContext = context;
                  if (!mounted || !currentContext.mounted) return;
                  final success = await viewModel.uploadPhotoToSession();
                  if (!mounted || !currentContext.mounted) return;
                  if (success && viewModel.capturedPhoto != null) {
                    // Release camera native buffers (~300–600 MB) BEFORE
                    // navigating so the next screen doesn't overlap with
                    // camera heap on a 4 GB kiosk.
                    viewModel.disposeCamera();
                    final photo = viewModel.capturedPhoto!;
                    await Navigator.pushNamed(
                      currentContext,
                      AppConstants.kRouteHome,
                      arguments: ThemeSelectionArgs(photo: photo),
                    );
                    // User came back (Back from ThemeSelection). Re-initialize camera.
                    if (!mounted || !currentContext.mounted) return;
                    await _resetAndInitializeCameras();
                  }
                },
          child: viewModel.isUploading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Text('Continue'),
        ),
      ],
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
            onPressed: () => viewModel.clearCapturedPhoto(),
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

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isPhotoUploadAllowed)
          ElevatedButton.icon(
            style: _captureScreenButtonStyle(),
            onPressed: (viewModel.isCapturing || viewModel.isSelectingFromGallery)
                ? null
                : () async => await viewModel.selectFromGallery(),
            icon: viewModel.isSelectingFromGallery
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(CupertinoIcons.photo, size: 20),
            label: const Text('Gallery'),
          ),
        if (isPhotoUploadAllowed) const SizedBox(width: 12),
        ElevatedButton.icon(
          style: _captureScreenButtonStyle(),
          onPressed: (viewModel.isCapturing || viewModel.isSelectingFromGallery || viewModel.isCountingDown)
              ? null
              : () async => await viewModel.capturePhotoWithCountdown(),
          icon: viewModel.isCapturing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Icon(CupertinoIcons.camera, size: 20),
          label: const Text('Capture'),
        ),
      ],
    );
  }

  /// Filters cameras to remove duplicates by display name and by logical device.
  /// Flutter on iOS can return multiple entries for the same logical camera (e.g. two "Front Camera");
  /// we keep one per display name so the list shows Back Camera, Front Camera, HP 4K once each.
  List<CameraDescription> _getUniqueCameras(
    List<CameraDescription> cameras,
    CaptureViewModel viewModel,
  ) {
    final uniqueCameras = <CameraDescription>[];
    final seenDisplayNames = <String>{};

    for (final camera in cameras) {
      final displayName = viewModel.getCameraDisplayName(camera);
      if (seenDisplayNames.contains(displayName)) {
        continue;
      }
      seenDisplayNames.add(displayName);
      uniqueCameras.add(camera);
    }

    return uniqueCameras;
  }
}
