import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'camera_selection_viewmodel.dart';
import '../../utils/constants.dart';
import '../../views/widgets/camera_card.dart';
import '../../views/widgets/app_theme.dart';
import '../../views/widgets/app_scaffold.dart';

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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop) {
          Navigator.pushReplacementNamed(
            context,
            AppConstants.kRouteTerms,
          );
        }
      },
      child: AppScaffold(
        title: 'Select Camera',
        showBackButton: true,
        onBackPressed: () {
          Navigator.pushReplacementNamed(
            context,
            AppConstants.kRouteTerms,
          );
        },
        child: Column(
          children: [
            Expanded(
              child: Consumer<CameraViewModel>(
                builder: (context, viewModel, child) {
                  if (viewModel.isLoading) {
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

                  return GridView.builder(
                    padding: EdgeInsets.all(isTablet ? 24.0 : 16.0),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 1,
                      mainAxisSpacing: 16.0,
                      childAspectRatio: 4.0,
                    ),
                    itemCount: viewModel.availableCameras.length,
                    itemBuilder: (context, index) {
                      final camera = viewModel.availableCameras[index];
                      final isSelected =
                          viewModel.selectedCamera?.camera.name ==
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
            ),
            Consumer<CameraViewModel>(
              builder: (context, cameraViewModel, child) {
                final canProceed = cameraViewModel.selectedCamera != null;

                return AppContinueButton(
                  onPressed: canProceed
                      ? () {
                          Navigator.pushNamed(
                            context,
                            AppConstants.kRouteCapture,
                          );
                        }
                      : null,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
