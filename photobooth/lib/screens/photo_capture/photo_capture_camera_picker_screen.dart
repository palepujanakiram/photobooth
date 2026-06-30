import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/app_strings.dart';
import 'photo_capture_camera_selection_helpers.dart';
import 'photo_capture_viewmodel.dart';

/// Camera list with force-refresh on open and a manual refresh action.
class PhotoCaptureCameraPickerScreen extends StatefulWidget {
  const PhotoCaptureCameraPickerScreen({
    super.key,
    required this.viewModel,
  });

  final CaptureViewModel viewModel;

  @override
  State<PhotoCaptureCameraPickerScreen> createState() =>
      _PhotoCaptureCameraPickerScreenState();
}

class _PhotoCaptureCameraPickerScreenState
    extends State<PhotoCaptureCameraPickerScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshCameras());
    });
  }

  Future<void> _refreshCameras() async {
    await widget.viewModel.refreshCameraEnumeration();
    if (!mounted) return;
    if (widget.viewModel.availableCameras.isEmpty &&
        !widget.viewModel.isLoadingCameras) {
      await widget.viewModel.reportCameraNotFound(
        reason: 'No cameras found in picker',
      );
    }
    if (mounted) setState(() {});
  }

  void _selectCamera(CameraDescription camera) {
    final vm = widget.viewModel;
    if (vm.currentCamera?.name == camera.name) return;
    Navigator.pop(context, camera);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.viewModel,
      child: Consumer<CaptureViewModel>(
        builder: (context, vm, _) {
          final uniqueCameras = uniqueCamerasByDisplayName(
            vm.availableCameras,
            vm.getCameraDisplayName,
          );
          final usbHint = cameraPickerUsbHint(
            deviceType: vm.deviceType,
            cameras: vm.availableCameras,
          );
          final isRefreshing = vm.isLoadingCameras;

          return Scaffold(
            appBar: AppBar(
              centerTitle: true,
              title: const Text(AppStrings.selectCameraTitle),
              leading: IconButton(
                icon: const Icon(CupertinoIcons.xmark),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                IconButton(
                  icon: isRefreshing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(CupertinoIcons.arrow_clockwise),
                  tooltip: AppStrings.refreshCameras,
                  onPressed:
                      isRefreshing ? null : () => unawaited(_refreshCameras()),
                ),
              ],
            ),
            body: SafeArea(
              child: _buildBody(
                uniqueCameras: uniqueCameras,
                usbHint: usbHint,
                isRefreshing: isRefreshing,
                currentCameraName: vm.currentCamera?.name,
                displayNameFor: vm.getCameraDisplayName,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody({
    required List<CameraDescription> uniqueCameras,
    required String? usbHint,
    required bool isRefreshing,
    required String? currentCameraName,
    required String Function(CameraDescription camera) displayNameFor,
  }) {
    if (isRefreshing && uniqueCameras.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(AppStrings.cameraPickerRefreshing),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (usbHint != null) _buildHintBanner(usbHint),
        if (uniqueCameras.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              AppStrings.cameraPickerNoCameras,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          )
        else
          ...uniqueCameras.map((camera) {
            final isActive = currentCameraName == camera.name;
            final displayName = displayNameFor(camera);
            return ListTile(
              title: Text(displayName),
              leading: isActive
                  ? const Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      color: Colors.blue,
                    )
                  : null,
              onTap: () => _selectCamera(camera),
            );
          }),
      ],
    );
  }

  Widget _buildHintBanner(String message) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Material(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }
}
