import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'photo_capture_viewmodel.dart';
import '../camera_selection/camera_selection_viewmodel.dart';
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
      _initializeCamera();
    });
  }

  Future<void> _initializeCamera() async {
    final cameraViewModel = context.read<CameraViewModel>();
    final selectedCamera = cameraViewModel.selectedCamera;
    if (selectedCamera != null) {
      await _captureViewModel.initializeCamera(selectedCamera);
    }
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
        navigationBar: const AppTopBar(
          title: 'Capture Photo',
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
                      onPressed: () => _initializeCamera(),
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
                if (viewModel.capturedPhoto != null)
                  Positioned.fill(
                    child: Container(
                        color: CupertinoColors.black,
                      child: Center(
                        child: Image.file(
                          viewModel.capturedPhoto!.imageFile,
                          fit: BoxFit.contain,
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
}
