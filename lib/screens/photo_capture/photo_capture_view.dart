import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'photo_capture_viewmodel.dart';
import '../../utils/constants.dart';
import '../../utils/logger.dart';
import '../../views/widgets/app_theme.dart';
import '../../views/widgets/app_colors.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resetAndInitializeCameras();
    });
  }

  /// Common function to reset and initialize cameras
  /// Used both when entering the screen and when tapping the reload button
  Future<void> _resetAndInitializeCameras() async {
    await _captureViewModel.resetAndInitializeCameras();
  }

  @override
  void dispose() {
    _captureViewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _captureViewModel,
      child: Consumer<CaptureViewModel>(
        builder: (context, viewModel, child) {
          return CupertinoPageScaffold(
            navigationBar: AppTopBar(
              title: 'Capture Photo',
              leading: AppActionButton(
                icon: CupertinoIcons.back,
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
              actions: [
                AppActionButton(
                  icon: CupertinoIcons.arrow_clockwise,
                  onPressed:
                      viewModel.isLoadingCameras || viewModel.isInitializing
                          ? null
                          : () async {
                              await _resetAndInitializeCameras();
                            },
                  color:
                      (viewModel.isLoadingCameras || viewModel.isInitializing)
                          ? CupertinoColors.systemGrey
                          : CupertinoColors.activeBlue,
                ),
              ],
            ),
        child: SafeArea(
          child: Builder(
            builder: (context) {
              final viewModel = Provider.of<CaptureViewModel>(context, listen: true);
              if (viewModel.isInitializing) {
                return const Center(
                  child: CupertinoActivityIndicator(),
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
                // Use Texture widget for custom controller
                final textureIdValue = textureId; // Local variable to avoid null check warning
                AppLogger.debug('📺 Building Texture preview widget with texture ID: $textureIdValue');
                // Texture widget must explicitly fill its parent
                // Use LayoutBuilder to get available size and ensure proper rendering
                previewWidget = LayoutBuilder(
                  builder: (context, constraints) {
                    AppLogger.debug('📺 Texture widget constraints: ${constraints.maxWidth}x${constraints.maxHeight}');
                    return SizedBox(
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      child: Texture(
                        textureId: textureIdValue,
                        key: ValueKey('texture_$textureIdValue'),
                        filterQuality: FilterQuality.medium,
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
                  // Debug info overlay (top-left corner)
                  if (viewModel.isReady)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.of(context).backgroundColor.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '📷 Camera Ready',
                              style: TextStyle(
                                color: AppColors.of(context).primaryColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Custom: ${viewModel.cameraService.isUsingCustomController}',
                              style: TextStyle(
                                color: AppColors.of(context).textColor,
                                fontSize: 9,
                              ),
                            ),
                            if (viewModel.cameraService.isUsingCustomController)
                              Text(
                                'Preview: ${viewModel.cameraService.customController?.isPreviewRunning ?? false}',
                                style: TextStyle(
                                  color: (viewModel.cameraService.customController?.isPreviewRunning ?? false)
                                      ? AppColors.of(context).primaryColor
                                      : AppColors.of(context).errorColor,
                                  fontSize: 9,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  // Camera switch buttons at the top
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      bottom: false,
                      child: _buildCameraSwitchButtons(context, viewModel),
                    ),
                  ),
                  if (viewModel.capturedPhoto != null)
                    Positioned.fill(
                      child: Container(
                        color: AppColors.of(context).backgroundColor,
                        child: Center(
                          child: FutureBuilder<List<int>>(
                            future: viewModel.capturedPhoto!.imageFile
                                .readAsBytes(),
                            builder: (context, snapshot) {
                              final appColors = AppColors.of(context);
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return CupertinoActivityIndicator(
                                  color: appColors.textColor,
                                );
                              }
                              if (snapshot.hasError || !snapshot.hasData) {
                                return Icon(
                                  CupertinoIcons.exclamationmark_triangle,
                                  color: appColors.errorColor,
                                );
                              }
                              return Image.memory(
                                Uint8List.fromList(snapshot.data!),
                                fit: BoxFit.contain,
                              );
                            },
                          ),
                        ),
                      ),
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
          );
        },
      ),
    );
  }

  Widget _buildCaptureControls(
      BuildContext context, CaptureViewModel viewModel) {
    final appColors = AppColors.of(context);

    if (viewModel.capturedPhoto != null) {
      return Padding(
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
                Row(
                  children: [
                    const Icon(
                      CupertinoIcons.exclamationmark_triangle_fill,
                      color: CupertinoColors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
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
                  minSize: 0,
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
        // Capture and Gallery buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Gallery button
            CupertinoButton(
              onPressed: viewModel.isCapturing
                  ? null
                  : () async {
                      await viewModel.selectFromGallery();
                    },
              padding: EdgeInsets.zero,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: appColors.surfaceColor.withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: appColors.primaryColor.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: viewModel.isCapturing
                    ? CupertinoActivityIndicator(
                        color: appColors.textColor,
                      )
                    : Icon(
                        CupertinoIcons.photo,
                        color: appColors.textColor,
                        size: 28,
                      ),
              ),
            ),
            
            const SizedBox(width: 24),
            
            // Capture button (main)
            CupertinoButton(
              onPressed: viewModel.isCapturing
                  ? null
                  : () async {
                      await viewModel.capturePhoto();
                    },
              padding: EdgeInsets.zero,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: appColors.surfaceColor,
                  shape: BoxShape.circle,
                ),
                child: viewModel.isCapturing
                    ? CupertinoActivityIndicator(
                        color: appColors.textColor,
                      )
                    : Icon(
                        CupertinoIcons.camera,
                        color: appColors.textColor,
                        size: 40,
                      ),
              ),
            ),
            
            const SizedBox(width: 84), // Balance the layout (60 + 24)
          ],
        ),
      ],
    );
  }

  Widget _buildCameraSwitchButtons(
      BuildContext context, CaptureViewModel viewModel) {
    if (viewModel.availableCameras.length <= 1) {
      // Don't show buttons if there's only one camera
      return const SizedBox.shrink();
    }

    // Filter out duplicate cameras - keep only unique cameras by lens direction
    // For built-in cameras, we want max 2: front and back
    final uniqueCameras = _getUniqueCameras(viewModel.availableCameras);

    // Limit to max 4 cameras (2x2 grid)
    final camerasToShow = uniqueCameras.take(4).toList();

    if (camerasToShow.isEmpty) {
      return const SizedBox.shrink();
    }

    final appColors = AppColors.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Calculate button width based on available space
          // Max 2 buttons per row, with spacing
          final buttonWidth =
              (constraints.maxWidth - 48) / 2; // 48 = padding + spacing
          const buttonHeight = 40.0;

          return Wrap(
            alignment: WrapAlignment.center,
            spacing: 8.0,
            runSpacing: 8.0,
            children: camerasToShow.map((camera) {
              final isActive = viewModel.currentCamera?.name == camera.name;

              return SizedBox(
                width: buttonWidth,
                height: buttonHeight,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: viewModel.isInitializing
                      ? null
                      : () async {
                          AppLogger.debug(
                              '🔘 Camera button tapped: ${camera.name} (${camera.lensDirection})');
                          await viewModel.switchCamera(camera);
                        },
                  color: isActive
                      ? appColors.primaryColor
                      : appColors.surfaceColor.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(20),
                  child: Text(
                    _getCameraShortName(viewModel, camera),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.normal,
                      color: isActive
                          ? appColors.buttonTextColor
                          : appColors.textColor,
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  /// Filters cameras to remove duplicates
  /// Keeps only one camera per lens direction for built-in cameras
  /// Allows multiple external cameras, but deduplicates them properly
  List<CameraDescription> _getUniqueCameras(List<CameraDescription> cameras) {
    // Show: 1 front camera, 1 back camera, and all unique external cameras
    final uniqueCameras = <CameraDescription>[];
    bool hasFront = false;
    bool hasBack = false;

    // Normalize camera name to extract unique ID for comparison
    String normalizeCameraId(CameraDescription camera) {
      // For Android: "Camera 5" -> "5", "5" -> "5"
      final nameMatch = RegExp(r'Camera\s*(\d+)').firstMatch(camera.name);
      if (nameMatch != null) {
        return nameMatch.group(1)!;
      }
      // For iOS: might be UUID or device ID format
      // If it contains ":", extract the device ID part
      if (camera.name.contains(':')) {
        return camera.name.split(':').last.split(',').first.trim();
      }
      // Otherwise use the name as-is
      return camera.name;
    }

    // Track seen cameras by normalized ID and direction
    final seenCameraKeys = <String>{};

    for (final camera in cameras) {
      final isExternal = camera.lensDirection == CameraLensDirection.external;
      final isFront = camera.lensDirection == CameraLensDirection.front;
      final isBack = camera.lensDirection == CameraLensDirection.back;

      if (isExternal) {
        // For external cameras, use normalized ID to deduplicate
        final normalizedId = normalizeCameraId(camera);
        final cameraKey = 'external:$normalizedId';
        
        if (!seenCameraKeys.contains(cameraKey)) {
          uniqueCameras.add(camera);
          seenCameraKeys.add(cameraKey);
          AppLogger.debug('   ✅ Added external camera: ${camera.name} (normalized ID: $normalizedId)');
        } else {
          AppLogger.debug('   ⏭️ Skipped duplicate external camera: ${camera.name} (normalized ID: $normalizedId already seen)');
        }
      } else if (isFront && !hasFront) {
        // Add first front camera
        uniqueCameras.add(camera);
        hasFront = true;
        seenCameraKeys.add('front');
        AppLogger.debug('   ✅ Added front camera: ${camera.name}');
      } else if (isBack && !hasBack) {
        // Add first back camera
        uniqueCameras.add(camera);
        hasBack = true;
        seenCameraKeys.add('back');
        AppLogger.debug('   ✅ Added back camera: ${camera.name}');
      }
    }

    return uniqueCameras;
  }


  String _getCameraShortName(
      CaptureViewModel viewModel, CameraDescription camera) {
    // Use the camera service to get the localized/display name
    final displayName = viewModel.cameraService.getCameraDisplayName(camera);

    // Truncate long names to fit in button (max 15 characters)
    if (displayName.length > 15) {
      return '${displayName.substring(0, 12)}...';
    }

    return displayName;
  }
}
