import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_switch_freeze_helpers.dart';

void main() {
  test('shouldShowCameraSwitchFreezeFrame only during an in-flight switch', () {
    expect(
      shouldShowCameraSwitchFreezeFrame(
        hasFreezeFrame: true,
        switchInProgress: true,
        hasCapturedPhoto: false,
        isSelectingFromGallery: false,
      ),
      isTrue,
    );
    expect(
      shouldShowCameraSwitchFreezeFrame(
        hasFreezeFrame: false,
        switchInProgress: true,
        hasCapturedPhoto: false,
        isSelectingFromGallery: false,
      ),
      isFalse,
    );
    expect(
      shouldShowCameraSwitchFreezeFrame(
        hasFreezeFrame: true,
        switchInProgress: false,
        hasCapturedPhoto: false,
        isSelectingFromGallery: false,
      ),
      isFalse,
    );
    expect(
      shouldShowCameraSwitchFreezeFrame(
        hasFreezeFrame: true,
        switchInProgress: true,
        hasCapturedPhoto: true,
        isSelectingFromGallery: false,
      ),
      isFalse,
    );
    expect(
      shouldShowCameraSwitchFreezeFrame(
        hasFreezeFrame: true,
        switchInProgress: true,
        hasCapturedPhoto: false,
        isSelectingFromGallery: true,
      ),
      isFalse,
    );
  });

  test('cameraSwitchFreezeBoundaryKey prefers sidecar then UVC then plugin', () {
    final sidecar = GlobalKey();
    final uvc = GlobalKey();
    final plugin = GlobalKey();
    expect(
      cameraSwitchFreezeBoundaryKey(
        useSidecarPosePreview: true,
        isUsingUvc: true,
        sidecarKey: sidecar,
        uvcKey: uvc,
        pluginKey: plugin,
      ),
      sidecar,
    );
    expect(
      cameraSwitchFreezeBoundaryKey(
        useSidecarPosePreview: false,
        isUsingUvc: true,
        sidecarKey: sidecar,
        uvcKey: uvc,
        pluginKey: plugin,
      ),
      uvc,
    );
    expect(
      cameraSwitchFreezeBoundaryKey(
        useSidecarPosePreview: false,
        isUsingUvc: false,
        sidecarKey: sidecar,
        uvcKey: uvc,
        pluginKey: plugin,
      ),
      plugin,
    );
  });

  test('resolveCaptureLivePreviewKind prefers freeze over live sources', () {
    expect(
      resolveCaptureLivePreviewKind(
        isSelectingFromGallery: true,
        hasCapturedPhoto: true,
        showSwitchFreeze: true,
        useSidecarPosePreview: true,
        isUsingUvc: true,
        hasCameraController: true,
      ),
      CaptureLivePreviewKind.gallery,
    );
    expect(
      resolveCaptureLivePreviewKind(
        isSelectingFromGallery: false,
        hasCapturedPhoto: true,
        showSwitchFreeze: true,
        useSidecarPosePreview: true,
        isUsingUvc: true,
        hasCameraController: true,
      ),
      CaptureLivePreviewKind.capturedStill,
    );
    expect(
      resolveCaptureLivePreviewKind(
        isSelectingFromGallery: false,
        hasCapturedPhoto: false,
        showSwitchFreeze: true,
        useSidecarPosePreview: true,
        isUsingUvc: true,
        hasCameraController: true,
      ),
      CaptureLivePreviewKind.switchFreeze,
    );
    expect(
      resolveCaptureLivePreviewKind(
        isSelectingFromGallery: false,
        hasCapturedPhoto: false,
        showSwitchFreeze: false,
        useSidecarPosePreview: true,
        isUsingUvc: true,
        hasCameraController: false,
      ),
      CaptureLivePreviewKind.sidecar,
    );
    expect(
      resolveCaptureLivePreviewKind(
        isSelectingFromGallery: false,
        hasCapturedPhoto: false,
        showSwitchFreeze: false,
        useSidecarPosePreview: false,
        isUsingUvc: true,
        hasCameraController: false,
      ),
      CaptureLivePreviewKind.uvc,
    );
    expect(
      resolveCaptureLivePreviewKind(
        isSelectingFromGallery: false,
        hasCapturedPhoto: false,
        showSwitchFreeze: false,
        useSidecarPosePreview: false,
        isUsingUvc: false,
        hasCameraController: false,
      ),
      CaptureLivePreviewKind.startingPlaceholder,
    );
    expect(
      resolveCaptureLivePreviewKind(
        isSelectingFromGallery: false,
        hasCapturedPhoto: false,
        showSwitchFreeze: false,
        useSidecarPosePreview: false,
        isUsingUvc: false,
        hasCameraController: true,
      ),
      CaptureLivePreviewKind.pluginCamera,
    );
  });

  testWidgets('captureRepaintBoundaryImage returns null without a boundary',
      (tester) async {
    expect(await captureRepaintBoundaryImage(boundaryKey: GlobalKey()), isNull);
  });

  testWidgets('captureRepaintBoundaryImage returns null for an empty boundary',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 0,
              height: 0,
              child: RepaintBoundary(
                key: key,
                child: const ColoredBox(color: Colors.red),
              ),
            ),
          ),
        ),
      ),
    );
    expect(await captureRepaintBoundaryImage(boundaryKey: key), isNull);
  });

  testWidgets('captureRepaintBoundaryImage captures painted pixels',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: RepaintBoundary(
              key: key,
              child: const ColoredBox(color: Colors.red),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final image = await captureRepaintBoundaryImage(
      boundaryKey: key,
      maxLongEdge: 12,
    );
    expect(image, isNotNull);
    expect(image!.width, greaterThan(0));
    expect(image.height, greaterThan(0));
    image.dispose();
  });

  testWidgets(
      'captureRepaintBoundaryImage returns null when the key is not a boundary',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(key: key, width: 24, height: 24),
      ),
    );
    expect(await captureRepaintBoundaryImage(boundaryKey: key), isNull);
  });

  testWidgets('captureRepaintBoundaryImage returns null when capture throws',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: RepaintBoundary(
              key: key,
              child: const ColoredBox(color: Colors.red),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      await captureRepaintBoundaryImage(
        boundaryKey: key,
        captureImage: (_, __) async => throw StateError('capture failed'),
      ),
      isNull,
    );
  });
}
