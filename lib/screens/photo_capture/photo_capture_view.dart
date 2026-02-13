import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'photo_capture_viewmodel.dart';
import '../../utils/constants.dart';
import '../../utils/logger.dart';
import '../../views/widgets/app_theme.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/full_screen_loader.dart';

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
      _resetAndInitializeCameras();
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
  Future<void> _resetAndInitializeCameras() async {
    await _captureViewModel.resetAndInitializeCameras();
  }

  @override
  void dispose() {
    _captureViewModel.dispose();
    super.dispose();
  }

  void _showCameraSelectionDialog(BuildContext context, CaptureViewModel viewModel) {
    final appColors = AppColors.of(context);
    final uniqueCameras = _getUniqueCameras(viewModel.availableCameras);
    
    if (uniqueCameras.isEmpty) {
      return;
    }

    showCupertinoModalPopup(
      context: context,
      builder: (dialogContext) => CupertinoActionSheet(
        title: const Text('Select Camera'),
        message: const Text('Choose a camera to use'),
        actions: uniqueCameras.map((camera) {
          final isActive = viewModel.currentCamera?.name == camera.name;
          final displayName = viewModel.cameraService.getCameraDisplayName(camera);
          
          return CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(dialogContext);
              if (!isActive) {
                await viewModel.switchCamera(camera);
              }
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isActive)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      color: CupertinoColors.systemBlue,
                      size: 20,
                    ),
                  ),
                Text(
                  displayName,
                  style: TextStyle(
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    color: isActive ? CupertinoColors.systemBlue : appColors.textColor,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
      ),
    );
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
}

/// Helper class to store step information
class _StepInfo {
  final IconData icon;
  final String label;

  _StepInfo({required this.icon, required this.label});
}
