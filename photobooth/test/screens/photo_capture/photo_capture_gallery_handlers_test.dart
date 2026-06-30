import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_gallery_handlers.dart';

void main() {
  test('buildGallerySelectionPlaceholder renders without error', () {
    expect(buildGallerySelectionPlaceholder(), isA<Widget>());
  });

  test('pauseCapturePreviewForGallery disposes CameraX session', () async {
    var disposed = false;

    await pauseCapturePreviewForGallery(
      disposeCamera: () async => disposed = true,
    );

    expect(disposed, isTrue);
  });

  test('finalizeGallerySelection disposes camera when photo accepted', () async {
    var disposed = false;

    await finalizeGallerySelection(
      photoAccepted: true,
      disposeCamera: () async => disposed = true,
    );

    expect(disposed, isTrue);
  });

  test('finalizeGallerySelection no-op when gallery cancelled', () async {
    var disposed = false;

    await finalizeGallerySelection(
      photoAccepted: false,
      disposeCamera: () async => disposed = true,
    );

    expect(disposed, isFalse);
  });

  test('resumeCapturePreviewAfterGallery restores built-in preview', () async {
    var resumed = false;

    await resumeCapturePreviewAfterGallery(
      hasCapturedPhoto: false,
      resumeBuiltInPreview: () async => resumed = true,
    );

    expect(resumed, isTrue);
  });

  test('resumeCapturePreviewAfterGallery skips when photo was accepted', () async {
    var resumed = false;

    await resumeCapturePreviewAfterGallery(
      hasCapturedPhoto: true,
      resumeBuiltInPreview: () async => resumed = true,
    );

    expect(resumed, isFalse);
  });
}
