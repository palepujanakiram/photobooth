import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'camera_selection_viewmodel.dart';
import '../theme_selection/theme_selection_viewmodel.dart';
import '../../utils/constants.dart';
import '../../views/widgets/camera_card.dart';

class CameraSelectionScreen extends StatefulWidget {
  const CameraSelectionScreen({super.key});

  @override
  State<CameraSelectionScreen> createState() => _CameraSelectionScreenState();
}

class _CameraSelectionScreenState extends State<CameraSelectionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CameraViewModel>().loadCameras();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > AppConstants.kTabletBreakpoint;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Camera'),
        centerTitle: true,
      ),
      body: Consumer<CameraViewModel>(
        builder: (context, viewModel, child) {
          if (viewModel.isLoading) {
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
                    onPressed: () => viewModel.loadCameras(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (viewModel.availableCameras.isEmpty) {
            return const Center(
              child: Text('No cameras available'),
            );
          }

          return ListView.builder(
            padding: EdgeInsets.all(isTablet ? 24.0 : 16.0),
            itemCount: viewModel.availableCameras.length,
            itemBuilder: (context, index) {
              final camera = viewModel.availableCameras[index];
              final isSelected = viewModel.selectedCamera?.camera.name ==
                  camera.camera.name;

              return CameraCard(
                camera: camera,
                isSelected: isSelected,
                onTap: () {
                  viewModel.selectCamera(camera);
                },
              );
            },
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Consumer2<CameraViewModel, ThemeViewModel>(
          builder: (context, cameraViewModel, themeViewModel, child) {
            final canProceed = cameraViewModel.selectedCamera != null &&
                themeViewModel.selectedTheme != null;

            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton(
                onPressed: canProceed
                    ? () {
                        Navigator.pushNamed(
                          context,
                          AppConstants.kRouteCapture,
                        );
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity,
                      AppConstants.kButtonHeight),
                ),
                child: const Text('Continue'),
              ),
            );
          },
        ),
      ),
    );
  }
}

