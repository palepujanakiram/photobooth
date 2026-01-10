import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'take_photo_viewmodel.dart';
import '../../views/widgets/app_theme.dart';
import '../../views/widgets/app_colors.dart';

class TakePhotoScreen extends StatefulWidget {
  const TakePhotoScreen({super.key});

  @override
  State<TakePhotoScreen> createState() => _TakePhotoScreenState();
}

class _TakePhotoScreenState extends State<TakePhotoScreen> {
  late TakePhotoViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = TakePhotoViewModel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Add a small delay to ensure navigation is complete before loading cameras
      // This helps prevent exceptions during navigation
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _viewModel.loadCameras().catchError((error) {
            // Handle any errors during camera loading
            debugPrint('Error loading cameras: $error');
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Consumer<TakePhotoViewModel>(
        builder: (context, viewModel, child) {
          return CupertinoPageScaffold(
            navigationBar: AppTopBar(
              title: 'Take Photo',
              leading: AppActionButton(
                icon: CupertinoIcons.back,
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
              actions: [
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
              child: _buildBody(context, viewModel),
            ),
          );
        },
      ),
    );
  }

  /// Builds the main body content based on view model state
  Widget _buildBody(BuildContext context, TakePhotoViewModel viewModel) {
    if (viewModel.isLoadingCameras) {
      return _buildLoadingView();
    }

    if (viewModel.hasError && viewModel.availableCameras.isEmpty) {
      return _buildErrorView(context, viewModel);
    }

    if (viewModel.isInitializing) {
      return _buildInitializingView(context);
    }

    if (viewModel.capturedPhoto != null) {
      return _buildCapturedPhotoView(context, viewModel);
    }

    return _buildCameraView(context, viewModel);
  }

  /// Builds the loading indicator view
  Widget _buildLoadingView() {
    return const Center(
      child: CupertinoActivityIndicator(),
    );
  }

  /// Builds the error view
  Widget _buildErrorView(BuildContext context, TakePhotoViewModel viewModel) {
    final appColors = AppColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
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
              onPressed: () => viewModel.loadCameras(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the initializing view
  Widget _buildInitializingView(BuildContext context) {
    final appColors = AppColors.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CupertinoActivityIndicator(),
          const SizedBox(height: 16),
          Text(
            'Initializing camera...',
            style: TextStyle(color: appColors.textColor),
          ),
        ],
      ),
    );
  }

  /// Builds the captured photo view
  Widget _buildCapturedPhotoView(BuildContext context, TakePhotoViewModel viewModel) {
    final appColors = AppColors.of(context);
    return Column(
      children: [
        Expanded(
          child: Center(
            child: FutureBuilder<List<int>>(
              future: viewModel.capturedPhoto!.imageFile.readAsBytes(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return CupertinoActivityIndicator(color: appColors.textColor);
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
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              CupertinoButton(
                onPressed: () {
                  viewModel.clearCapturedPhoto();
                },
                color: CupertinoColors.systemGrey,
                child: const Text('Retake'),
              ),
              CupertinoButton(
                onPressed: () {
                  // Return the captured photo
                  Navigator.pop(context, viewModel.capturedPhoto);
                },
                color: appColors.primaryColor,
                child: const Text('Use Photo'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Builds the main camera view with selection buttons, preview, and capture button
  Widget _buildCameraView(BuildContext context, TakePhotoViewModel viewModel) {
    return Column(
      children: [
        // Camera selection buttons
        _buildCameraSelectionButtons(context, viewModel),
        // Camera preview
        Expanded(
          child: _buildCameraPreview(context, viewModel),
        ),
        // Capture button
        _buildCaptureButton(context, viewModel),
      ],
    );
  }

  /// Builds camera selection buttons
  Widget _buildCameraSelectionButtons(BuildContext context, TakePhotoViewModel viewModel) {
    if (viewModel.availableCameras.isEmpty) {
      return const SizedBox.shrink();
    }

    final appColors = AppColors.of(context);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: viewModel.availableCameras.map((camera) {
            final isSelected = viewModel.selectedCamera?.name == camera.name;
            final displayName = _getCameraDisplayName(context, camera);
            
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                onPressed: viewModel.isInitializing
                    ? null
                    : () async {
                        await viewModel.selectCamera(camera);
                      },
                color: isSelected
                    ? appColors.primaryColor
                    : appColors.surfaceColor.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
                child: Text(
                  displayName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected
                        ? appColors.buttonTextColor
                        : appColors.textColor,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  /// Builds the camera preview widget
  Widget _buildCameraPreview(BuildContext context, TakePhotoViewModel viewModel) {
    final appColors = AppColors.of(context);
    
    // Show error message if there's an error
    if (viewModel.hasError && viewModel.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                CupertinoIcons.exclamationmark_triangle,
                size: 48,
                color: appColors.errorColor,
              ),
              const SizedBox(height: 16),
              Text(
                viewModel.errorMessage!,
                style: TextStyle(
                  fontSize: 14,
                  color: appColors.textColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              CupertinoButton(
                onPressed: () async {
                  if (viewModel.selectedCamera != null) {
                    await viewModel.selectCamera(viewModel.selectedCamera!);
                  }
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    
    if (!viewModel.isReady) {
      return Center(
        child: Text(
          'Camera not ready',
          style: TextStyle(color: appColors.textColor),
        ),
      );
    }

    // Check if using UVC camera
    if (viewModel.isUsingUvcCamera && viewModel.cameraService.uvcCameraWrapper != null) {
      return _buildUvcCameraPreview(viewModel.cameraService.uvcCameraWrapper!);
    }
    // Check if using custom controller (Texture widget)
    else if (viewModel.isUsingCustomController && viewModel.textureId != null) {
      return _buildTexturePreview(viewModel.textureId!);
    } 
    // Use standard CameraPreview
    else if (viewModel.cameraController != null) {
      return _buildStandardCameraPreview(viewModel);
    } 
    // Placeholder
    else {
      final appColors = AppColors.of(context);
      return Container(
        color: appColors.backgroundColor,
        child: Center(
          child: Text(
            'Camera preview not available',
            style: TextStyle(color: appColors.textColor),
          ),
        ),
      );
    }
  }

  /// Builds UVC camera preview widget
  Widget _buildUvcCameraPreview(uvcCameraWrapper) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: uvcCameraWrapper.createView(),
        );
      },
    );
  }

  /// Builds Texture widget for custom controller preview
  Widget _buildTexturePreview(int textureId) {
    return LayoutBuilder(
      builder: (context, constraints) {
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
  Widget _buildStandardCameraPreview(TakePhotoViewModel viewModel) {
    return CameraPreview(viewModel.cameraController!);
  }

  /// Builds the capture button
  Widget _buildCaptureButton(BuildContext context, TakePhotoViewModel viewModel) {
    final appColors = AppColors.of(context);
    
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Center(
        child: CupertinoButton(
          onPressed: viewModel.isCapturing || !viewModel.isReady
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
      ),
    );
  }

  /// Gets display name for camera
  String _getCameraDisplayName(BuildContext context, CameraDescription camera) {
    final viewModel = Provider.of<TakePhotoViewModel>(context, listen: false);
    return viewModel.cameraService.getCameraDisplayName(camera);
  }
}
