import 'package:flutter/material.dart';

import 'photo_capture_uvc_feed_phase.dart';

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

/// Stops UVC / built-in preview before opening the gallery picker.
Future<void> pauseCapturePreviewForGallery({
  required bool isUsingUvc,
  required Future<void> Function() closeUvc,
  required Future<void> Function() disposeBuiltInCamera,
  required void Function(UvcFeedPhase phase) setUvcPhase,
  required void Function() cancelUvcSessionRecycle,
}) async {
  cancelUvcSessionRecycle();
  if (isUsingUvc) {
    setUvcPhase(UvcFeedPhase.capturing);
    await closeUvc();
    return;
  }
  await disposeBuiltInCamera();
}

/// Keeps preview closed after a gallery photo is accepted (review still).
Future<void> finalizeGallerySelection({
  required bool isUsingUvc,
  required bool photoAccepted,
  required Future<void> Function() closeUvc,
  required Future<void> Function() disposeBuiltInCamera,
  required void Function(UvcFeedPhase phase) setUvcPhase,
  required void Function() cancelUvcReconnect,
  required void Function() bumpPreviewGeneration,
}) async {
  if (!photoAccepted) return;
  if (isUsingUvc) {
    cancelUvcReconnect();
    setUvcPhase(UvcFeedPhase.reviewing);
    await closeUvc();
    bumpPreviewGeneration();
    return;
  }
  await disposeBuiltInCamera();
}

/// Restores live preview when gallery selection is cancelled or fails.
Future<void> resumeCapturePreviewAfterGallery({
  required bool isUsingUvc,
  required bool hasCapturedPhoto,
  required void Function(UvcFeedPhase phase) setUvcPhase,
  required Future<void> Function(String reason) resumeUvcLiveFeed,
  required Future<void> Function() resumeBuiltInPreview,
}) async {
  if (hasCapturedPhoto) return;
  if (isUsingUvc) {
    setUvcPhase(UvcFeedPhase.live);
    await resumeUvcLiveFeed('galleryCancelled');
    return;
  }
  await resumeBuiltInPreview();
}
