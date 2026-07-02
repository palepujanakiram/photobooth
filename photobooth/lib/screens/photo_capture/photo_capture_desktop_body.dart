import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'photo_capture_viewmodel.dart';

/// Capture UI when the `camera` plugin is unavailable (Windows desktop).
class PhotoCaptureDesktopBody extends StatelessWidget {
  const PhotoCaptureDesktopBody({
    super.key,
    required this.viewModel,
    required this.onTakePhoto,
    required this.onPickGallery,
    required this.showGallery,
  });

  final CaptureViewModel viewModel;
  final VoidCallback onTakePhoto;
  final VoidCallback onPickGallery;
  final bool showGallery;

  @override
  Widget build(BuildContext context) {
    final photo = viewModel.capturedPhoto;
    if (photo != null) {
      return const SizedBox.shrink();
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.camera_fill,
              size: 72,
              color: Colors.white.withValues(alpha: 0.9),
            ),
            const SizedBox(height: 20),
            Text(
              'Windows photo booth',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.95),
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Use your webcam or pick a photo to continue.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 15,
                height: 1.35,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 280,
              child: CupertinoButton.filled(
                onPressed: viewModel.isCapturing || viewModel.isSelectingFromGallery
                    ? null
                    : onTakePhoto,
                child: viewModel.isCapturing
                    ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                    : const Text('Take Photo'),
              ),
            ),
            if (showGallery) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: 280,
                child: CupertinoButton(
                  onPressed: viewModel.isCapturing || viewModel.isSelectingFromGallery
                      ? null
                      : onPickGallery,
                  child: viewModel.isSelectingFromGallery
                      ? const CupertinoActivityIndicator()
                      : const Text('Choose from Gallery'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
