import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:camera_native_details/camera_native_details.dart';
import 'photo_capture_viewmodel.dart';
import 'photo_image_from_xfile_io.dart' if (dart.library.html) 'photo_image_from_xfile_web.dart' as photo_image;
import '../../utils/constants.dart';
import '../../utils/image_helper.dart';
import '../../utils/device_classifier.dart';
import '../../views/widgets/app_theme.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/full_screen_loader.dart';
import '../../views/widgets/bottom_safe_area.dart';
import 'photo_capture_rotation_screen.dart';

class PhotoCaptureScreen extends StatefulWidget {
  const PhotoCaptureScreen({super.key});

  @override
  State<PhotoCaptureScreen> createState() => _PhotoCaptureScreenState();
}

class _PhotoCaptureScreenState extends State<PhotoCaptureScreen> {
  late CaptureViewModel _captureViewModel;

  @override
  void initState() {
    super.initState();
    _captureViewModel = CaptureViewModel();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _captureViewModel.loadPreviewRotation();
      await _resetAndInitializeCameras();
    });
  }

  /// Common function to reset and initialize cameras
  /// Used both when entering the screen and when tapping the reload button
  /// Uses sync tablet check so cameras load immediately; does not block on slow getDeviceType().
  Future<void> _resetAndInitializeCameras({bool forceRefresh = false}) async {
    if (!mounted) return;
    _captureViewModel.setDeviceType(null);
    final deviceTypeFuture = DeviceClassifier.getDeviceType(context);
    await _captureViewModel.resetAndInitializeCameras(
      forceRefresh: forceRefresh,
    );
    if (!mounted) return;
    try {
      final deviceType = await deviceTypeFuture;
      if (mounted) _captureViewModel.setDeviceType(deviceType);
    } catch (_) {}
  }

  @override
  void dispose() {
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
          return Scaffold(
                appBar: AppTopBar(
                  title: 'Capture Photo',
                  leading: AppActionButton(
                    icon: CupertinoIcons.back,
                    onPressed: () => Navigator.pop(context),
                  ),
                  actions: [
                    if (viewModel.availableCameras.length > 1)
                      AppActionButton(
                        icon: CupertinoIcons.camera_rotate,
                        onPressed: viewModel.isLoadingCameras || viewModel.isInitializing
                            ? null
                            : () => _showCameraSelectionDialog(context, viewModel),
                        color: (viewModel.isLoadingCameras || viewModel.isInitializing)
                            ? Colors.grey
                            : Colors.blue,
                      ),
                    AppActionButton(
                      icon: CupertinoIcons.rotate_right,
                      onPressed: viewModel.isLoadingCameras || viewModel.isInitializing
                          ? null
                          : () => _openPreviewRotationScreen(context, viewModel),
                      color: (viewModel.isLoadingCameras || viewModel.isInitializing)
                          ? Colors.grey
                          : Colors.blue,
                    ),
                    AppActionButton(
                      icon: CupertinoIcons.arrow_clockwise,
                      onPressed: viewModel.isLoadingCameras || viewModel.isInitializing
                          ? null
                          : () => _resetAndInitializeCameras(forceRefresh: true),
                      color: (viewModel.isLoadingCameras || viewModel.isInitializing)
                          ? Colors.grey
                          : Colors.blue,
                    ),
                  ],
                ),
                body: SizedBox.expand(
                  child: SafeArea(
                    top: true,
                    bottom: false,
                    child: Builder(
                    builder: (context) {
                      final viewModel = Provider.of<CaptureViewModel>(context, listen: true);
                      // "Detecting cameras…" full-screen state like fluttercamerabasic (loading gate)
                      if (viewModel.isLoadingCameras) {
                        return Container(
                          color: Colors.black,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(color: Colors.white),
                                const SizedBox(height: 20),
                                Text(
                                  'Detecting cameras…',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      if (viewModel.isInitializing) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (viewModel.availableCameras.isEmpty && !viewModel.hasError) {
                        return const Center(child: CircularProgressIndicator());
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
                                style: TextStyle(
                                  fontSize: 16,
                                  color: appColors.textColor,
                                ),
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

                      if (!viewModel.isReady) {
                        final appColors = AppColors.of(context);
                        return Center(
                          child: Text(
                            'Camera not ready',
                            style: TextStyle(color: appColors.textColor),
                          ),
                        );
                      }

                      final Widget previewWidget = _buildCameraPreviewWithRotation(context, viewModel);
                      final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
                      final badgeTop = isLandscape ? 8.0 : 12.0;
                      final badgeRight = isLandscape ? 8.0 : 12.0;
                      final detailsBottom = isLandscape ? 90.0 : 180.0;
                      final photoInfoBottom = isLandscape ? 70.0 : 100.0;
                      final controlsBottomPadding = (isLandscape ? 16.0 : 32.0) + effectiveBottomInset(context);

                      final captureControlsPositioned = Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: SafeArea(
                          top: false,
                          bottom: true,
                          child: Padding(
                            padding: EdgeInsets.only(bottom: controlsBottomPadding),
                            child: _buildCaptureControls(context, viewModel),
                          ),
                        ),
                      );

                      return Stack(
                        children: [
                          Positioned.fill(
                            child: previewWidget,
                          ),
                          // Display rotation badge (compact position in landscape)
                          Positioned(
                            top: badgeTop,
                            right: badgeRight,
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: isLandscape ? 8 : 10, vertical: isLandscape ? 4 : 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _effectiveRotationLabel(viewModel),
                                style: TextStyle(color: Colors.white70, fontSize: isLandscape ? 11 : 12),
                              ),
                            ),
                          ),
                          if (viewModel.capturedPhoto != null)
                            Positioned.fill(
                              child: Container(
                                color: AppColors.of(context).backgroundColor,
                                child: Center(
                                  child: _buildCapturedPhotoDisplay(context, viewModel),
                                ),
                              ),
                            ),
                          // Step banner at the top (compact in landscape)
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: _buildStepBanner(context, 0, isLandscape), // 0 = Photo step
                          ),
                          // Countdown overlay
                          if (viewModel.isCountingDown)
                            Positioned.fill(
                              child: _buildCountdownOverlay(context, viewModel.countdownValue!),
                            ),
                          // Native camera details (preview size etc.) — visible until photo is captured
                          if (viewModel.nativeCameraDetails != null && viewModel.capturedPhoto == null)
                            Positioned(
                              left: isLandscape ? 8 : 12,
                              bottom: detailsBottom,
                              child: _buildNativeCameraDetailsCard(
                                context,
                                viewModel.nativeCameraDetails!,
                                previewSize: viewModel.previewSize,
                                resolutionPreset: viewModel.effectiveResolutionPreset,
                                currentZoom: viewModel.currentZoom,
                              ),
                            ),
                          // Captured photo info (resolution, file size) — only after capture
                          if (viewModel.capturedPhoto != null)
                            Positioned(
                              left: isLandscape ? 8 : 16,
                              bottom: photoInfoBottom,
                              child: _buildCapturedPhotoDetailsOverlay(context, viewModel),
                            ),
                          captureControlsPositioned,
                          viewModel.isUploading
                              ? Positioned.fill(
                                  child: FullScreenLoader(
                                    text: 'Uploading Photo',
                                    loaderColor: Colors.blue,
                                    elapsedSeconds: viewModel.uploadElapsedSeconds,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ],
                      );
                    },
                  ),
                ),
                ),
              );
        },
      ),
    );
  }

  /// Builds the step progress banner (compact in landscape)
  Widget _buildStepBanner(BuildContext context, int currentStep, [bool compact = false]) {
    final appColors = AppColors.of(context);
    
    final steps = [
      _StepInfo(icon: CupertinoIcons.camera, label: 'Photo'),
      _StepInfo(icon: CupertinoIcons.paintbrush, label: 'Select Theme'),
      _StepInfo(icon: CupertinoIcons.sparkles, label: 'Generate'),
      _StepInfo(icon: CupertinoIcons.tray_arrow_down, label: 'Pay & Collect'),
    ];

    final bannerPadding = compact ? const EdgeInsets.symmetric(vertical: 6, horizontal: 6) : const EdgeInsets.symmetric(vertical: 12, horizontal: 8);
    return Container(
      padding: bannerPadding,
      decoration: BoxDecoration(
        color: appColors.backgroundColor,
        boxShadow: [
          BoxShadow(
            color: appColors.shadowColor.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(steps.length, (index) {
          final step = steps[index];
          final isActive = index == currentStep;
          final isCompleted = index < currentStep;
          
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: compact ? 28.0 : 36,
                        height: compact ? 28.0 : 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isActive 
                              ? Colors.blue.withValues(alpha: 0.1)
                              : isCompleted
                                  ? Colors.blue
                                  : Colors.transparent,
                          border: Border.all(
                            color: isActive || isCompleted
                                ? Colors.blue
                                : Colors.grey.shade400,
                            width: isActive ? 2 : 1,
                          ),
                        ),
                        child: Icon(
                          isCompleted ? CupertinoIcons.checkmark : step.icon,
                          size: compact ? 14.0 : 18,
                          color: isCompleted
                              ? Colors.white
                              : isActive
                                  ? Colors.blue
                                  : Colors.grey,
                        ),
                      ),
                      SizedBox(height: compact ? 2 : 4),
                      Text(
                        step.label,
                        style: TextStyle(
                          fontSize: compact ? 9 : 10,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                          color: isActive || isCompleted
                              ? Colors.blue
                              : Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Connector line (except for last item)
                if (index < steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 1,
                      margin: EdgeInsets.only(bottom: compact ? 14.0 : 20),
                      color: isCompleted
                          ? Colors.blue
                          : Colors.grey.shade400,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
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

    final previewSize = controller.value.previewSize;
    final baseAspectRatio = controller.value.aspectRatio;
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

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: ClipRect(
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.fill,
              child: SizedBox(
                width: width,
                height: height,
                child: preview,
              ),
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

  /// Builds the captured photo display. Uses file path for immediate display (no 2s delay).
  Widget _buildCapturedPhotoDisplay(BuildContext context, CaptureViewModel viewModel) {
    final photo = viewModel.capturedPhoto;
    if (photo == null) return const SizedBox.shrink();
    return photo_image.imageFromXFile(photo.imageFile);
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

  /// Captured photo info (resolution, file size). Shown only after photo is captured.
  Widget _buildCapturedPhotoDetailsOverlay(
    BuildContext context,
    CaptureViewModel viewModel,
  ) {
    final photo = viewModel.capturedPhoto;
    if (photo == null) return const SizedBox.shrink();

    return FutureBuilder<ImageMetadata?>(
      future: ImageHelper.getImageMetadata(photo.imageFile),
      builder: (context, snapshot) {
        final meta = snapshot.data;
        if (meta == null && snapshot.connectionState != ConnectionState.done) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Loading…',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          );
        }
        if (meta == null) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Resolution: ${meta.width} × ${meta.height}',
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'File size: ${ImageHelper.formatFileSize(meta.fileSizeBytes)}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        );
      },
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

  Widget _buildCaptureControls(
      BuildContext context, CaptureViewModel viewModel) {
    final appColors = AppColors.of(context);

    if (viewModel.capturedPhoto != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Cancel/Retake button
                SizedBox(
                  width: 120,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => viewModel.clearCapturedPhoto(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: appColors.buttonTextColor,
                      ),
                    ),
                  ),
                ),
                // Continue button
                SizedBox(
                  width: 120,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: appColors.primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: (viewModel.isCapturing || viewModel.isUploading)
                        ? null
                        : () async {
                            // Capture context before async operation
                            final currentContext = context;

                            if (!mounted || !currentContext.mounted) return;

                            // Upload photo to session and trigger preprocessing
                            final success = await viewModel.uploadPhotoToSession();

                            if (!mounted || !currentContext.mounted) return;

                            if (success) {
                              // Navigate to Theme Selection screen
                              Navigator.pushNamed(
                                currentContext,
                                AppConstants.kRouteHome,
                                arguments: {
                                  'photo': viewModel.capturedPhoto,
                                },
                              );
                            } else {
                              // Show error message (error is already set in viewModel)
                              // The error will be displayed in the error UI
                            }
                          },
                    child: viewModel.isUploading
                        ? CircularProgressIndicator(
                            color: appColors.buttonTextColor,
                          )
                        : Text(
                            'Continue',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: appColors.buttonTextColor,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Error message display above button
        if (viewModel.hasError && viewModel.errorMessage != null)
          Container(
            margin: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: appColors.errorColor.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      CupertinoIcons.exclamationmark_triangle,
                      color: Colors.white,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Error',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  viewModel.errorMessage!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    viewModel.clearCapturedPhoto(); // This also clears error
                  },
                  child: Text(
                    'Dismiss',
                    style: TextStyle(
                      color: appColors.errorColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // Gallery and Capture buttons with labels
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Gallery button (LEFT)
              _buildActionButton(
                context: context,
                icon: CupertinoIcons.photo,
                label: 'Gallery',
                isLoading: viewModel.isSelectingFromGallery,
                isDisabled: viewModel.isCapturing || viewModel.isSelectingFromGallery,
                onPressed: () async {
                  await viewModel.selectFromGallery();
                },
                appColors: appColors,
              ),
              
              // Spacer to push capture button to center
              const Spacer(),
              
              // Capture button (CENTER)
              _buildActionButton(
                context: context,
                icon: CupertinoIcons.camera,
                label: 'Capture',
                isLoading: viewModel.isCapturing,
                isDisabled: viewModel.isCapturing || viewModel.isSelectingFromGallery || viewModel.isCountingDown,
                onPressed: () async {
                  await viewModel.capturePhotoWithCountdown();
                },
                appColors: appColors,
                isPrimary: true,
              ),
              
              // Spacer to balance the layout
              const Spacer(),
              
              // Empty space to balance Gallery button width
              const SizedBox(width: 60), // Same width as Gallery button
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required bool isLoading,
    required bool isDisabled,
    required VoidCallback onPressed,
    required AppColors appColors,
    bool isPrimary = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: isDisabled ? null : onPressed,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: isPrimary ? 80 : 60,
            height: isPrimary ? 80 : 60,
            decoration: BoxDecoration(
              color: isPrimary 
                  ? appColors.primaryColor 
                  : appColors.surfaceColor.withValues(alpha: 0.8),
              shape: BoxShape.circle,
              border: Border.all(
                color: isPrimary 
                    ? appColors.primaryColor 
                    : appColors.primaryColor.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: isLoading
                ? CircularProgressIndicator(
                    color: isPrimary ? Colors.white : appColors.textColor,
                  )
                : Icon(
                    icon,
                    color: isPrimary ? Colors.white : appColors.textColor,
                    size: isPrimary ? 40 : 28,
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: appColors.textColor,
          ),
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

/// Helper class to store step information
class _StepInfo {
  final IconData icon;
  final String label;

  _StepInfo({required this.icon, required this.label});
}
