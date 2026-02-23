import 'dart:math' show pi;
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'photo_capture_viewmodel.dart';
import '../../services/camera_service.dart';
import '../../utils/constants.dart';
import '../../utils/device_classifier.dart';
import '../../utils/image_helper.dart';
import '../../utils/logger.dart';
import '../../views/widgets/app_theme.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/full_screen_loader.dart';
import 'photo_capture_rotation_screen.dart';

class PhotoCaptureScreen extends StatefulWidget {
  const PhotoCaptureScreen({super.key});

  @override
  State<PhotoCaptureScreen> createState() => _PhotoCaptureScreenState();
}

class _PhotoCaptureScreenState extends State<PhotoCaptureScreen> {
  late CaptureViewModel _captureViewModel;
  Uint8List? _cachedImageBytes;
  String? _cachedPhotoId;

  @override
  void initState() {
    super.initState();
    _captureViewModel = CaptureViewModel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _captureViewModel.loadPreviewRotation();
        _resetAndInitializeCameras();
      }
    });
  }

  /// Loads and caches the captured photo bytes
  Future<void> _loadCapturedPhotoBytes() async {
    final photo = _captureViewModel.capturedPhoto;
    if (photo == null) {
      _cachedImageBytes = null;
      _cachedPhotoId = null;
      return;
    }
    
    // Only reload if photo changed
    if (_cachedPhotoId != photo.id) {
      try {
        final bytes = await photo.imageFile.readAsBytes();
        if (mounted) {
          setState(() {
            _cachedImageBytes = Uint8List.fromList(bytes);
            _cachedPhotoId = photo.id;
          });
        }
      } catch (e) {
        // Handle error silently
      }
    }
  }

  /// Common function to reset and initialize cameras
  /// Used both when entering the screen and when tapping the reload button
  /// Uses sync tablet check so cameras load immediately; does not block on slow getDeviceType().
  Future<void> _resetAndInitializeCameras() async {
    if (!mounted) return;
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    _captureViewModel.setTabletOrTv(shortestSide >= AppConstants.kTabletBreakpoint);
    _captureViewModel.setDeviceType(null);
    await _captureViewModel.resetAndInitializeCameras();
    // Optionally refine device type in background (e.g. for Android TV); no need to reload cameras
    if (!mounted) return;
    try {
      final deviceType = await DeviceClassifier.getDeviceType(context);
      if (mounted) _captureViewModel.setDeviceType(deviceType);
    } catch (_) {}
  }

  @override
  void dispose() {
    _captureViewModel.dispose();
    super.dispose();
  }

  void _showCameraSelectionDialog(BuildContext context, CaptureViewModel viewModel) {
    final uniqueCameras = _getUniqueCameras(viewModel.availableCameras, viewModel.cameraService);
    if (uniqueCameras.isEmpty) return;

    Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (pickerContext) => CupertinoPageScaffold(
          navigationBar: CupertinoNavigationBar(
            middle: const Text('Select Camera'),
            leading: CupertinoButton(
              padding: EdgeInsets.zero,
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(pickerContext),
            ),
          ),
          child: SafeArea(
            child: ListView.builder(
              itemCount: uniqueCameras.length,
              itemBuilder: (_, index) {
                final camera = uniqueCameras[index];
                final isActive = viewModel.currentCamera?.name == camera.name;
                final displayName = viewModel.cameraService.getCameraDisplayName(camera);
                return CupertinoListTile(
                  title: Text(displayName),
                  leading: isActive
                      ? const Icon(CupertinoIcons.checkmark_circle_fill, color: CupertinoColors.activeBlue)
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
      CupertinoPageRoute<int>(
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
          return Stack(
            children: [
              CupertinoPageScaffold(
                navigationBar: AppTopBar(
                  title: 'Capture Photo',
                  leading: AppActionButton(
                    icon: CupertinoIcons.back,
                    onPressed: () {
                      Navigator.pop(context);
                    },
                  ),
                  actions: [
                    // Camera selection button
                    if (viewModel.availableCameras.length > 1)
                      AppActionButton(
                        icon: CupertinoIcons.camera_rotate,
                        onPressed: viewModel.isLoadingCameras || viewModel.isInitializing
                            ? null
                            : () => _showCameraSelectionDialog(context, viewModel),
                        color: (viewModel.isLoadingCameras || viewModel.isInitializing)
                            ? CupertinoColors.systemGrey
                            : CupertinoColors.activeBlue,
                      ),
                    // Preview rotation button (for external camera)
                    AppActionButton(
                      icon: CupertinoIcons.rotate_right,
                      onPressed: viewModel.isLoadingCameras || viewModel.isInitializing
                          ? null
                          : () => _openPreviewRotationScreen(context, viewModel),
                      color: (viewModel.isLoadingCameras || viewModel.isInitializing)
                          ? CupertinoColors.systemGrey
                          : CupertinoColors.activeBlue,
                    ),
                    // Refresh button
                    AppActionButton(
                      icon: CupertinoIcons.arrow_clockwise,
                      onPressed: viewModel.isLoadingCameras || viewModel.isInitializing
                          ? null
                          : () async {
                              await _resetAndInitializeCameras();
                            },
                      color: (viewModel.isLoadingCameras || viewModel.isInitializing)
                          ? CupertinoColors.systemGrey
                          : CupertinoColors.activeBlue,
                    ),
                  ],
                ),
                child: SafeArea(
                  top: true,
                  bottom: false,
                  child: Builder(
                    builder: (context) {
                      final viewModel = Provider.of<CaptureViewModel>(context, listen: true);
                      if (viewModel.isInitializing) {
                        return const Center(child: CupertinoActivityIndicator());
                      }
                      if (viewModel.availableCameras.isEmpty && !viewModel.hasError) {
                        return const Center(child: CupertinoActivityIndicator());
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
                              CupertinoButton(
                                onPressed: () => _resetAndInitializeCameras(),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        );
                      }

                      // Check if using custom controller (for external cameras)
                      final isUsingCustomController = viewModel.cameraService.isUsingCustomController;
                      final textureId = viewModel.cameraService.textureId;
                      
                      // Debug logging
                      AppLogger.debug('📺 Preview widget state:');
                      AppLogger.debug('   isUsingCustomController: $isUsingCustomController');
                      AppLogger.debug('   textureId: $textureId');
                      AppLogger.debug('   viewModel.isReady: ${viewModel.isReady}');
                      AppLogger.debug('   viewModel.cameraController: ${viewModel.cameraController != null}');
                      
                      if (!viewModel.isReady) {
                        final appColors = AppColors.of(context);
                        AppLogger.debug('📺 Camera not ready - showing placeholder');
                        return Center(
                          child: Text(
                            'Camera not ready',
                            style: TextStyle(color: appColors.textColor),
                          ),
                        );
                      }

                      // Build preview widget
                      Widget previewWidget;
                      if (isUsingCustomController && textureId != null) {
                        // External camera stream is 16:9. Apply user-chosen rotation (saved in preferences).
                        final textureIdValue = textureId;
                        const streamAspectRatio = 16 / 9;
                        final rotationRad = viewModel.previewRotationDegrees * pi / 180;
                        previewWidget = LayoutBuilder(
                          builder: (context, constraints) {
                            return Center(
                              child: Transform.rotate(
                                angle: rotationRad,
                                child: FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    width: constraints.maxWidth,
                                    height: constraints.maxWidth / streamAspectRatio,
                                    child: Texture(
                                      textureId: textureIdValue,
                                      key: ValueKey('texture_$textureIdValue'),
                                      filterQuality: FilterQuality.medium,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      } else if (viewModel.cameraController != null) {
                        // Use standard CameraPreview
                        AppLogger.debug('📺 Building standard CameraPreview widget');
                        previewWidget = CameraPreview(viewModel.cameraController!);
                      } else {
                        AppLogger.debug('📺 No camera controller available - showing placeholder');
                        previewWidget = Container(
                          color: AppColors.of(context).backgroundColor,
                          child: Center(
                            child: Text(
                              'Camera preview not available',
                              style: TextStyle(
                                color: AppColors.of(context).textColor,
                              ),
                            ),
                          ),
                        );
                      }

                      return Stack(
                        children: [
                          // Preview widget - must fill the entire stack
                          Positioned.fill(
                            child: previewWidget,
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
                          // Step banner at the top (always visible, on top of captured photo)
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: _buildStepBanner(context, 0), // 0 = Photo step
                          ),
                          // Countdown overlay
                          if (viewModel.isCountingDown)
                            Positioned.fill(
                              child: _buildCountdownOverlay(context, viewModel.countdownValue!),
                            ),
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: SafeArea(
                              top: false,
                              bottom: true,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 32.0),
                                child: _buildCaptureControls(context, viewModel),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              // Full screen loader overlay for uploading
              if (viewModel.isUploading)
                Positioned.fill(
                  child: FullScreenLoader(
                    text: 'Uploading Photo',
                    loaderColor: CupertinoColors.systemBlue,
                    elapsedSeconds: viewModel.uploadElapsedSeconds,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Builds the step progress banner
  Widget _buildStepBanner(BuildContext context, int currentStep) {
    final appColors = AppColors.of(context);
    
    final steps = [
      _StepInfo(icon: CupertinoIcons.camera, label: 'Photo'),
      _StepInfo(icon: CupertinoIcons.paintbrush, label: 'Select Theme'),
      _StepInfo(icon: CupertinoIcons.sparkles, label: 'Generate'),
      _StepInfo(icon: CupertinoIcons.tray_arrow_down, label: 'Pay & Collect'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
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
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isActive 
                              ? CupertinoColors.systemBlue.withValues(alpha: 0.1)
                              : isCompleted
                                  ? CupertinoColors.systemBlue
                                  : Colors.transparent,
                          border: Border.all(
                            color: isActive || isCompleted
                                ? CupertinoColors.systemBlue
                                : CupertinoColors.systemGrey3,
                            width: isActive ? 2 : 1,
                          ),
                        ),
                        child: Icon(
                          isCompleted ? CupertinoIcons.checkmark : step.icon,
                          size: 18,
                          color: isCompleted
                              ? CupertinoColors.white
                              : isActive
                                  ? CupertinoColors.systemBlue
                                  : CupertinoColors.systemGrey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        step.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                          color: isActive || isCompleted
                              ? CupertinoColors.systemBlue
                              : CupertinoColors.systemGrey,
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
                      margin: const EdgeInsets.only(bottom: 20),
                      color: isCompleted
                          ? CupertinoColors.systemBlue
                          : CupertinoColors.systemGrey3,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  /// Builds the captured photo display using cached bytes
  Widget _buildCapturedPhotoDisplay(BuildContext context, CaptureViewModel viewModel) {
    final appColors = AppColors.of(context);
    final photo = viewModel.capturedPhoto;
    
    if (photo == null) {
      return const SizedBox.shrink();
    }
    
    // Load image bytes if not cached or photo changed
    if (_cachedPhotoId != photo.id) {
      // Trigger async load
      _loadCapturedPhotoBytes();
      
      // Show loading while bytes are being loaded
      return CupertinoActivityIndicator(
        color: appColors.textColor,
      );
    }
    
    // Show cached image
    if (_cachedImageBytes != null) {
      return Image.memory(
        _cachedImageBytes!,
        fit: BoxFit.contain,
        gaplessPlayback: true, // Prevents flickering
      );
    }
    
    // Fallback: show loading
    return CupertinoActivityIndicator(
      color: appColors.textColor,
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
                color: CupertinoColors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Overlay above Cancel/Continue showing photo size (width × height) and format.
  Widget _buildPhotoMetadataOverlay(
    BuildContext context,
    XFile imageFile,
    AppColors appColors,
  ) {
    return FutureBuilder<ImageMetadata?>(
      future: ImageHelper.getImageMetadata(imageFile),
      builder: (context, snapshot) {
        final meta = snapshot.data;
        if (meta == null) {
          return const SizedBox.shrink();
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: CupertinoColors.systemGrey6.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: CupertinoColors.systemGrey4,
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '${meta.width} × ${meta.height}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: appColors.textColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                meta.format,
                style: TextStyle(
                  fontSize: 12,
                  color: appColors.textColor.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                ImageHelper.formatFileSize(meta.fileSizeBytes),
                style: TextStyle(
                  fontSize: 12,
                  color: appColors.textColor.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCaptureControls(
      BuildContext context, CaptureViewModel viewModel) {
    final appColors = AppColors.of(context);

    if (viewModel.capturedPhoto != null) {
      final photo = viewModel.capturedPhoto!;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (AppConstants.kShowCapturedPhotoMetadataOverlay)
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: _buildPhotoMetadataOverlay(context, photo.imageFile, appColors),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Cancel/Retake button
                SizedBox(
                  width: 120,
                  height: 50,
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      // Clear cached image bytes
                      setState(() {
                        _cachedImageBytes = null;
                        _cachedPhotoId = null;
                      });
                      viewModel.clearCapturedPhoto();
                    },
                    color: CupertinoColors.systemGrey,
                    borderRadius: BorderRadius.circular(12),
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
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
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
                    color: appColors.primaryColor,
                    disabledColor: CupertinoColors.systemGrey3,
                    borderRadius: BorderRadius.circular(12),
                    child: viewModel.isUploading
                        ? CupertinoActivityIndicator(
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
                      CupertinoIcons.exclamationmark_triangle_fill,
                      color: CupertinoColors.white,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Error',
                      style: TextStyle(
                        color: CupertinoColors.white,
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
                    color: CupertinoColors.white,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: CupertinoColors.white,
                  borderRadius: BorderRadius.circular(8),
                  minimumSize: Size.zero,
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
        CupertinoButton(
          onPressed: isDisabled ? null : onPressed,
          padding: EdgeInsets.zero,
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
                ? CupertinoActivityIndicator(
                    color: isPrimary ? CupertinoColors.white : appColors.textColor,
                  )
                : Icon(
                    icon,
                    color: isPrimary ? CupertinoColors.white : appColors.textColor,
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
    CameraService cameraService,
  ) {
    final uniqueCameras = <CameraDescription>[];
    final seenDisplayNames = <String>{};

    for (final camera in cameras) {
      final displayName = cameraService.getCameraDisplayName(camera);
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
