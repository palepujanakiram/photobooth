import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_gallery_handlers.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_uvc_feed_phase.dart';

void main() {
  test('buildGallerySelectionPlaceholder renders without error', () {
    expect(buildGallerySelectionPlaceholder(), isA<Widget>());
  });

  test('pauseCapturePreviewForGallery closes UVC and blocks live phase', () async {
    var phase = UvcFeedPhase.live;
    var closed = false;
    var recycled = false;

    await pauseCapturePreviewForGallery(
      isUsingUvc: true,
      closeUvc: () async => closed = true,
      disposeBuiltInCamera: () async {},
      setUvcPhase: (next) => phase = next,
      cancelUvcSessionRecycle: () => recycled = true,
    );

    expect(closed, isTrue);
    expect(recycled, isTrue);
    expect(phase, UvcFeedPhase.capturing);
  });

  test('pauseCapturePreviewForGallery disposes built-in camera when not UVC', () async {
    var disposed = false;

    await pauseCapturePreviewForGallery(
      isUsingUvc: false,
      closeUvc: () async {},
      disposeBuiltInCamera: () async => disposed = true,
      setUvcPhase: (_) {},
      cancelUvcSessionRecycle: () {},
    );

    expect(disposed, isTrue);
  });

  test('finalizeGallerySelection enters reviewing and closes UVC', () async {
    var phase = UvcFeedPhase.live;
    var closed = false;
    var reconnected = false;
    var bumped = false;

    await finalizeGallerySelection(
      isUsingUvc: true,
      photoAccepted: true,
      closeUvc: () async => closed = true,
      disposeBuiltInCamera: () async {},
      setUvcPhase: (next) => phase = next,
      cancelUvcReconnect: () => reconnected = true,
      bumpPreviewGeneration: () => bumped = true,
    );

    expect(closed, isTrue);
    expect(reconnected, isTrue);
    expect(bumped, isTrue);
    expect(phase, UvcFeedPhase.reviewing);
  });

  test('finalizeGallerySelection no-op when gallery cancelled', () async {
    var phase = UvcFeedPhase.capturing;
    var closed = false;

    await finalizeGallerySelection(
      isUsingUvc: true,
      photoAccepted: false,
      closeUvc: () async => closed = true,
      disposeBuiltInCamera: () async {},
      setUvcPhase: (next) => phase = next,
      cancelUvcReconnect: () {},
      bumpPreviewGeneration: () {},
    );

    expect(closed, isFalse);
    expect(phase, UvcFeedPhase.capturing);
  });

  test('resumeCapturePreviewAfterGallery restores live UVC feed', () async {
    var phase = UvcFeedPhase.capturing;
    String? reason;

    await resumeCapturePreviewAfterGallery(
      isUsingUvc: true,
      hasCapturedPhoto: false,
      setUvcPhase: (next) => phase = next,
      resumeUvcLiveFeed: (r) async => reason = r,
      resumeBuiltInPreview: () async {},
    );

    expect(phase, UvcFeedPhase.live);
    expect(reason, 'galleryCancelled');
  });

  test('finalizeGallerySelection disposes built-in camera when not UVC', () async {
    var disposed = false;

    await finalizeGallerySelection(
      isUsingUvc: false,
      photoAccepted: true,
      closeUvc: () async {},
      disposeBuiltInCamera: () async => disposed = true,
      setUvcPhase: (_) {},
      cancelUvcReconnect: () {},
      bumpPreviewGeneration: () {},
    );

    expect(disposed, isTrue);
  });

  test('resumeCapturePreviewAfterGallery restores built-in preview', () async {
    var resumed = false;

    await resumeCapturePreviewAfterGallery(
      isUsingUvc: false,
      hasCapturedPhoto: false,
      setUvcPhase: (_) {},
      resumeUvcLiveFeed: (_) async {},
      resumeBuiltInPreview: () async => resumed = true,
    );

    expect(resumed, isTrue);
  });
}
