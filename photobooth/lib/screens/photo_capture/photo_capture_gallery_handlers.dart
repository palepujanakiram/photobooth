import 'package:flutter/material.dart';

/// Placeholder shown while the system gallery picker is open (no live preview).
Widget buildGallerySelectionPlaceholder() {
  return const ColoredBox(
    color: Colors.black,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 12),
          Text(
            'Selecting photo…',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    ),
  );
}

/// Stops CameraX preview before opening the gallery picker.
Future<void> pauseCapturePreviewForGallery({
  required Future<void> Function() disposeCamera,
}) async {
  await disposeCamera();
}

/// Keeps preview closed after a gallery photo is accepted (review still).
Future<void> finalizeGallerySelection({
  required bool photoAccepted,
  required Future<void> Function() disposeCamera,
}) async {
  if (!photoAccepted) return;
  await disposeCamera();
}

/// Restores live preview when gallery selection is cancelled or fails.
Future<void> resumeCapturePreviewAfterGallery({
  required bool hasCapturedPhoto,
  required Future<void> Function() resumeBuiltInPreview,
}) async {
  if (hasCapturedPhoto) return;
  await resumeBuiltInPreview();
}
