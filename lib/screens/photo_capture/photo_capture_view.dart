import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'photo_capture_viewmodel.dart';
import '../../utils/constants.dart';
import '../../views/widgets/app_theme.dart';

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
      _loadAndInitializeCamera();
    });
  }

  Future<void> _loadAndInitializeCamera() async {
    // Load available cameras
    await _captureViewModel.loadCameras();

    // Initialize with the first camera (or current camera if already set)
    if (_captureViewModel.availableCameras.isNotEmpty) {
      final cameraToUse = _captureViewModel.currentCamera ??
          _captureViewModel.availableCameras.first;
      await _captureViewModel.initializeCamera(cameraToUse);
    }
  }

  Future<void> _reloadCameras() async {
    print('🔄 Reload button tapped - refreshing camera list...');

    // Reload cameras and select the first one
    await _captureViewModel.reloadAndSelectFirstCamera();
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
      child: CupertinoPageScaffold(
        navigationBar: AppTopBar(
          title: 'Capture Photo',
          leading: AppActionButton(
            icon: CupertinoIcons.back,
            onPressed: () {
              Navigator.pop(context);
            },
          ),
          actions: [
            Consumer<CaptureViewModel>(
              builder: (context, viewModel, child) {
                return AppActionButton(
                  icon: CupertinoIcons.arrow_clockwise,
                  onPressed:
                      viewModel.isLoadingCameras || viewModel.isInitializing
                          ? null
                          : () async {
                              await _reloadCameras();
                            },
                  color:
                      (viewModel.isLoadingCameras || viewModel.isInitializing)
                          ? CupertinoColors.systemGrey
                          : CupertinoColors.activeBlue,
                );
              },
            ),
          ],
        ),
        child: SafeArea(
          child: Consumer<CaptureViewModel>(
            builder: (context, viewModel, child) {
              if (viewModel.isInitializing) {
                return const Center(
                  child: CupertinoActivityIndicator(),
                );
              }

              if (viewModel.hasError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        CupertinoIcons.exclamationmark_triangle,
                        size: 64,
                        color: CupertinoColors.systemRed,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        viewModel.errorMessage ?? 'Unknown error',
                        style: const TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      CupertinoButton(
                        onPressed: () => _loadAndInitializeCamera(),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }

              if (!viewModel.isReady || viewModel.cameraController == null) {
                return const Center(
                  child: Text('Camera not ready'),
                );
              }

              return Stack(
                children: [
                  Positioned.fill(
                    child: CameraPreview(viewModel.cameraController!),
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
                        color: CupertinoColors.black,
                        child: Center(
                          child: FutureBuilder<List<int>>(
                            future: viewModel.capturedPhoto!.imageFile
                                .readAsBytes(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const CupertinoActivityIndicator();
                              }
                              if (snapshot.hasError || !snapshot.hasData) {
                                return const Icon(
                                  CupertinoIcons.exclamationmark_triangle,
                                  color: CupertinoColors.systemRed,
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
      ),
    );
  }

  Widget _buildCaptureControls(
      BuildContext context, CaptureViewModel viewModel) {
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
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.white,
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

                        // Navigate to Theme Selection screen
                        Navigator.pushNamed(
                          currentContext,
                          AppConstants.kRouteHome,
                          arguments: {
                            'photo': viewModel.capturedPhoto,
                          },
                        );
                      },
                color: CupertinoColors.systemBlue,
                disabledColor: CupertinoColors.systemGrey3,
                borderRadius: BorderRadius.circular(12),
                child: viewModel.isUploading
                    ? const CupertinoActivityIndicator(
                        color: CupertinoColors.white,
                      )
                    : const Text(
                        'Continue',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: CupertinoColors.white,
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
          decoration: const BoxDecoration(
            color: CupertinoColors.white,
            shape: BoxShape.circle,
          ),
          child: viewModel.isCapturing
              ? const CupertinoActivityIndicator()
              : const Icon(
                  CupertinoIcons.camera,
                  color: CupertinoColors.black,
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: viewModel.availableCameras.map((camera) {
          final isActive = viewModel.currentCamera?.name == camera.name;

          // Debug: Log camera direction for each button
          print(
              'Camera: ${camera.name}, Direction: ${camera.lensDirection}');

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 8.0,
              ),
              onPressed: viewModel.isInitializing
                  ? null
                  : () async {
                      print(
                          '🔘 Camera button tapped: ${camera.name} (${camera.lensDirection})');
                      await viewModel.switchCamera(camera);
                    },
              color: isActive
                  ? CupertinoColors.activeBlue
                  : CupertinoColors.systemGrey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(20),
              child: Text(
                _getCameraShortName(camera.name),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  color:
                      isActive ? CupertinoColors.white : CupertinoColors.black,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _getCameraShortName(String fullName) {
    // Extract device ID from raw camera name
    // Format: "com.apple.avfoundation.avcapturedevice.built-in_video:8"
    if (fullName.contains(':')) {
      final deviceId = fullName.split(':').last.split(',').first;
      // Use device ID as short name (e.g., "8", "0", "1")
      return deviceId;
    }
    // Fallback: use last part of the name
    final parts = fullName.split('.');
    return parts.isNotEmpty ? parts.last : fullName;
  }

  Widget _buildCameraPreview(CaptureViewModel viewModel) {
    final cameraService = viewModel.cameraService;
    
    // Check if using custom controller
    if (cameraService.isUsingCustomController) {
      // For custom controller, we need a placeholder preview
      // TODO: Implement texture-based preview for custom controller
      return Container(
        color: CupertinoColors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CupertinoActivityIndicator(),
              SizedBox(height: 16),
              Text(
                'Camera Preview\n(Custom Controller Active)',
                textAlign: TextAlign.center,
                style: TextStyle(color: CupertinoColors.white),
              ),
            ],
          ),
        ),
      );
    }
    
    // Use standard CameraPreview widget
    if (viewModel.cameraController != null) {
      return CameraPreview(viewModel.cameraController!);
    }
    
    return Container(
      color: CupertinoColors.black,
      child: const Center(
        child: Text(
          'Camera not available',
          style: TextStyle(color: CupertinoColors.white),
        ),
      ),
    );
  }
}
