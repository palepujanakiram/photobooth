import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'photo_capture_viewmodel.dart';
import '../camera_selection/camera_selection_viewmodel.dart';
import '../theme_selection/theme_selection_viewmodel.dart';
import '../../utils/constants.dart';

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
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Capture Photo'),
          centerTitle: true,
        ),
        body: Consumer<CaptureViewModel>(
          builder: (context, viewModel, child) {
            if (viewModel.isInitializing) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            if (viewModel.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      viewModel.errorMessage ?? 'Unknown error',
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
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

            final bottomPadding = MediaQuery.of(context).padding.bottom;
            return Stack(
              children: [
                Positioned.fill(
                  child: CameraPreview(viewModel.cameraController!),
                ),
                if (viewModel.capturedPhoto != null)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black,
                      child: Center(
                        child: Image.file(
                          viewModel.capturedPhoto!.imageFile,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 32 + bottomPadding,
                  left: 0,
                  right: 0,
                  child: _buildCaptureControls(context, viewModel),
                ),
              ],
            );
          },
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
            ElevatedButton.icon(
              onPressed: () {
                viewModel.clearCapturedPhoto();
              },
              icon: const Icon(Icons.close),
              label: const Text('Retake'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
            ElevatedButton.icon(
              onPressed: viewModel.isCapturing
                  ? null
                  : () {
                      final themeViewModel = context.read<ThemeViewModel>();
                      Navigator.pushNamed(
                        context,
                        AppConstants.kRouteReview,
                        arguments: {
                          'photo': viewModel.capturedPhoto,
                          'theme': themeViewModel.selectedTheme,
                        },
                      );
                    },
              icon: const Icon(Icons.check),
              label: const Text('Continue'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return Center(
      child: FloatingActionButton.large(
        onPressed: viewModel.isCapturing
            ? null
            : () async {
                await viewModel.capturePhoto();
              },
        backgroundColor: Colors.white,
        child: viewModel.isCapturing
            ? const CircularProgressIndicator()
            : const Icon(Icons.camera_alt, color: Colors.black),
      ),
    );
  }
}

