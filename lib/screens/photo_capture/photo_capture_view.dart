import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
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
                AppActionButton(
                  icon: CupertinoIcons.settings,
                  onPressed: () async {
                    // Open app settings screen
                    await openAppSettings();
                  },
                  color: CupertinoColors.activeBlue,
                ),
              ],
            ),
        child: SafeArea(
          child: Builder(
            builder: (context) {
              final viewModel = Provider.of<CaptureViewModel>(context, listen: true);
              return _buildBody(context, viewModel);
            },
          ),
        ),
          );
        },
      ),
    );
  }

  /// Builds the main body content based on view model state
  Widget _buildBody(BuildContext context, CaptureViewModel viewModel) {
    if (viewModel.isInitializing) {
      return _buildLoadingView();
    }

    if (viewModel.hasError) {
      return _buildErrorView(context, viewModel);
    }

    if (!viewModel.isReady) {
      return _buildCameraNotReadyView(context);
    }

    return _buildCameraPreviewStack(context, viewModel);
  }

  /// Builds the loading indicator view
  Widget _buildLoadingView() {
    return const Center(
      child: CupertinoActivityIndicator(),
    );
  }

  /// Builds the error view with retry button
  Widget _buildErrorView(BuildContext context, CaptureViewModel viewModel) {
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

  /// Builds the camera not ready placeholder view
  Widget _buildCameraNotReadyView(BuildContext context) {
    final appColors = AppColors.of(context);
    AppLogger.debug('📺 Camera not ready - showing placeholder');
    return Center(
      child: Text(
        'Camera not ready',
        style: TextStyle(color: appColors.textColor),
      ),
    );
  }

  /// Builds the main camera preview stack with all overlays
  Widget _buildCameraPreviewStack(BuildContext context, CaptureViewModel viewModel) {
    return Stack(
      children: [
        // Camera preview - must fill the entire stack
        Positioned.fill(
          child: _buildCameraPreview(context, viewModel),
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
        // Captured photo overlay (if photo was taken)
        if (viewModel.capturedPhoto != null)
          _buildCapturedPhotoOverlay(context, viewModel),
        // Capture controls at the bottom
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
  }

  /// Builds the camera preview widget (Texture, CameraPreview, or placeholder)
  Widget _buildCameraPreview(BuildContext context, CaptureViewModel viewModel) {
    final isUsingCustomController = viewModel.cameraService.isUsingCustomController;
    final textureId = viewModel.cameraService.textureId;
    
    // Debug logging
    AppLogger.debug('📺 Preview widget state:');
    AppLogger.debug('   isUsingCustomController: $isUsingCustomController');
    AppLogger.debug('   textureId: $textureId');
    AppLogger.debug('   viewModel.isReady: ${viewModel.isReady}');
    AppLogger.debug('   viewModel.cameraController: ${viewModel.cameraController != null}');

    if (isUsingCustomController && textureId != null) {
      return _buildTexturePreview(textureId);
    } else if (viewModel.cameraController != null) {
      return _buildStandardCameraPreview(viewModel);
    } else {
      return _buildPreviewPlaceholder(context);
    }
  }

  /// Builds Texture widget for custom controller preview
  Widget _buildTexturePreview(int textureId) {
    AppLogger.debug('📺 Building Texture preview widget with texture ID: $textureId');
    return LayoutBuilder(
      builder: (context, constraints) {
        AppLogger.debug('📺 Texture widget constraints: ${constraints.maxWidth}x${constraints.maxHeight}');
        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: Texture(
            textureId: textureId,
            key: ValueKey('texture_$textureId'),
            filterQuality: FilterQuality.medium,
          ),
        );
      },
    );
  }

  /// Builds standard CameraPreview widget
  Widget _buildStandardCameraPreview(CaptureViewModel viewModel) {
    AppLogger.debug('📺 Building standard CameraPreview widget');
    return CameraPreview(viewModel.cameraController!);
  }

  /// Builds placeholder when no camera preview is available
  Widget _buildPreviewPlaceholder(BuildContext context) {
    AppLogger.debug('📺 No camera controller available - showing placeholder');
    final appColors = AppColors.of(context);
    return Container(
      color: appColors.backgroundColor,
      child: Center(
        child: Text(
          'Camera preview not available',
          style: TextStyle(
            color: appColors.textColor,
          ),
        ),
      ),
    );
  }

  /// Builds the captured photo overlay that shows the taken photo
  Widget _buildCapturedPhotoOverlay(BuildContext context, CaptureViewModel viewModel) {
    final appColors = AppColors.of(context);
    return Positioned.fill(
      child: Container(
        color: appColors.backgroundColor,
        child: Center(
          child: FutureBuilder<List<int>>(
            future: viewModel.capturedPhoto!.imageFile.readAsBytes(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
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

    return Center(
      child: CupertinoButton(
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
