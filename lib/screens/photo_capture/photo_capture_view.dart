import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'photo_capture_viewmodel.dart';
import '../../utils/constants.dart';
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
              
              if (!viewModel.isReady) {
                final appColors = AppColors.of(context);
                return Center(
                  child: Text(
                    'Camera not ready',
                    style: TextStyle(color: appColors.textColor),
                  ),
                );
              }

              // For custom controller, we need textureId
              if (isUsingCustomController && textureId == null) {
                final appColors = AppColors.of(context);
                return Center(
                  child: Text(
                    'Camera preview not available',
                    style: TextStyle(color: appColors.textColor),
                  ),
                );
              }

              // Build preview widget
              Widget previewWidget;
              if (isUsingCustomController && textureId != null) {
                final textureIdValue = textureId; // Local variable to avoid null check warning
                previewWidget = Texture(textureId: textureIdValue);
              } else if (viewModel.cameraController != null) {
                previewWidget = CameraPreview(viewModel.cameraController!);
              } else {
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
                  Positioned.fill(
                    child: previewWidget,
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
                          print(
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
  /// Allows multiple external cameras
  List<CameraDescription> _getUniqueCameras(List<CameraDescription> cameras) {
    // Show: 1 front camera, 1 back camera, and all external cameras
    final uniqueCameras = <CameraDescription>[];
    final seenDirections = <CameraLensDirection>{};
    bool hasFront = false;
    bool hasBack = false;

    // First pass: Add one front and one back camera (built-in)
    for (final camera in cameras) {
      final isBuiltIn = _isBuiltInCamera(camera);
      final isExternal = camera.lensDirection == CameraLensDirection.external;

      if (isBuiltIn && !isExternal) {
        // For built-in cameras, add one front and one back
        if (camera.lensDirection == CameraLensDirection.front && !hasFront) {
          uniqueCameras.add(camera);
          hasFront = true;
          seenDirections.add(camera.lensDirection);
        } else if (camera.lensDirection == CameraLensDirection.back && !hasBack) {
          uniqueCameras.add(camera);
          hasBack = true;
          seenDirections.add(camera.lensDirection);
        }
      }
    }

    // Second pass: Add all external cameras (deduplicate by camera ID, not name)
    // External cameras might have names like "Camera 5" or "5" - we need to deduplicate by ID
    final seenExternalIds = <String>{};
    for (final camera in cameras) {
      final isExternal = camera.lensDirection == CameraLensDirection.external;
      if (isExternal) {
        // Extract camera ID from name (handles both "Camera 5" and "5" formats)
        String cameraId;
        final nameMatch = RegExp(r'Camera\s*(\d+)').firstMatch(camera.name);
        if (nameMatch != null) {
          cameraId = nameMatch.group(1)!;
        } else {
          // Assume it's already a direct ID
          cameraId = camera.name;
        }
        
        // Only add if we haven't seen this camera ID before
        if (!seenExternalIds.contains(cameraId)) {
          uniqueCameras.add(camera);
          seenExternalIds.add(cameraId);
          print('   ✅ Added external camera: ${camera.name} (ID: $cameraId)');
        } else {
          print('   ⏭️ Skipped duplicate external camera: ${camera.name} (ID: $cameraId already seen)');
        }
      }
    }

    return uniqueCameras;
  }

  /// Checks if a camera is a built-in device camera
  bool _isBuiltInCamera(CameraDescription camera) {
    final name = camera.name;
    
    // On Android, Flutter camera names are like "Camera 0", "Camera 1", etc.
    // On iOS, camera names contain device IDs like "device:0"
    
    // Try to extract camera ID from Android format: "Camera 0" -> 0
    final androidMatch = RegExp(r'Camera\s*(\d+)').firstMatch(name);
    if (androidMatch != null) {
      final deviceId = int.tryParse(androidMatch.group(1)!);
      // Device IDs 0 and 1 are typically built-in cameras
      // IDs 2+ might be additional built-in cameras or external
      // External cameras should have lensDirection.external
      if (deviceId != null && deviceId <= 1) {
        return true;
      }
      // If it's external, it's not built-in
      if (camera.lensDirection == CameraLensDirection.external) {
        return false;
      }
    }
    
    // Try iOS format: "device:0" or similar
    if (name.contains(':')) {
      try {
        final deviceIdStr = name.split(':').last.split(',').first;
        final deviceId = int.tryParse(deviceIdStr);
        // Device IDs 0 and 1 are typically built-in cameras
        if (deviceId != null && deviceId <= 1) {
          return true;
        }
      } catch (e) {
        // If parsing fails, check by lens direction
      }
    }

    // If we can't determine by device ID, check if it's front or back
    // and we haven't seen this direction yet
    return camera.lensDirection == CameraLensDirection.front ||
        camera.lensDirection == CameraLensDirection.back;
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
