import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_preview_rotation.dart';

void main() {
  group('previewAutoQuarterTurnsForSensor', () {
    test('skips rotation for external USB/HDMI feeds', () {
      expect(
        previewAutoQuarterTurnsForSensor(
          applyAndroidRotationWorkaround: true,
          sensorOrientationDegrees: 90,
          isFrontCamera: false,
          isExternalFeed: true,
          displayRotationIndex: 1,
        ),
        0,
      );
    });

    test('applies tablet workaround for built-in back camera', () {
      expect(
        previewAutoQuarterTurnsForSensor(
          applyAndroidRotationWorkaround: true,
          sensorOrientationDegrees: 90,
          isFrontCamera: false,
          isExternalFeed: false,
          displayRotationIndex: 0,
        ),
        3,
      );
    });

    test('applies front-camera rotation formula', () {
      expect(
        previewAutoQuarterTurnsForSensor(
          applyAndroidRotationWorkaround: true,
          sensorOrientationDegrees: 270,
          isFrontCamera: true,
          isExternalFeed: false,
          displayRotationIndex: 2,
        ),
        3,
      );
    });

    test('returns zero when workaround disabled', () {
      expect(
        previewAutoQuarterTurnsForSensor(
          applyAndroidRotationWorkaround: false,
          sensorOrientationDegrees: 90,
          isFrontCamera: false,
          isExternalFeed: false,
          displayRotationIndex: 0,
        ),
        0,
      );
    });
  });

  test('previewDisplayDimensions null previewSize odd turns returns (1, ratio)',
      () {
    final (w, h) = previewDisplayDimensions(
      previewSize: null,
      effectiveQuarterTurns: 1,
      displayAspectRatio: 0.75,
    );
    expect(w, 1.0);
    expect(h, 0.75);
  });

  test('previewDisplayDimensions null previewSize even turns returns (ratio, 1)',
      () {
    final (w, h) = previewDisplayDimensions(
      previewSize: null,
      effectiveQuarterTurns: 0,
      displayAspectRatio: 1.5,
    );
    expect(w, 1.5);
    expect(h, 1.0);
  });

  test('previewDisplayDimensions swaps width and height for odd quarter turns',
      () {
    const frame = Size(1280, 720);
    final (w, h) = previewDisplayDimensions(
      previewSize: frame,
      effectiveQuarterTurns: 1,
      displayAspectRatio: 720 / 1280,
    );
    expect(w, 720);
    expect(h, 1280);
  });

  test('previewDisplayDimensions keeps dimensions for even quarter turns', () {
    const frame = Size(1280, 720);
    final (w, h) = previewDisplayDimensions(
      previewSize: frame,
      effectiveQuarterTurns: 0,
      displayAspectRatio: 1280 / 720,
    );
    expect(w, 1280);
    expect(h, 720);
  });

  test('cameraPreviewDisplayAspectRatio inverts for portrait UI', () {
    expect(
      cameraPreviewDisplayAspectRatio(
        controllerAspectRatio: 16 / 9,
        isLandscapeUi: false,
      ),
      closeTo(9 / 16, 0.0001),
    );
    expect(
      cameraPreviewDisplayAspectRatio(
        controllerAspectRatio: 16 / 9,
        isLandscapeUi: true,
      ),
      closeTo(16 / 9, 0.0001),
    );
    expect(
      cameraPreviewDisplayAspectRatio(
        controllerAspectRatio: 0,
        isLandscapeUi: false,
      ),
      1.0,
    );
  });

  testWidgets('buildCoverCameraPreview sizes child to contain in wide parent',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 520,
            child: buildCoverCameraPreview(
              cameraPreview: const ColoredBox(color: Colors.red),
              displayAspectRatio: 9 / 16,
            ),
          ),
        ),
      ),
    );
    expect(find.byType(ColoredBox), findsWidgets);
    final sized = tester.widget<SizedBox>(
      find.descendant(
        of: find.byType(Center),
        matching: find.byType(SizedBox),
      ).first,
    );
    // Parent 390×520 is wider than 9:16 → contain by matching height.
    expect(sized.height, closeTo(520, 0.1));
    expect(sized.width, closeTo(520 * (9 / 16), 0.5));
  });

  testWidgets('buildCoverCameraPreview contains tall parent via width branch', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 500,
            child: buildCoverCameraPreview(
              cameraPreview: const ColoredBox(color: Colors.green),
              displayAspectRatio: 1.5,
            ),
          ),
        ),
      ),
    );
    final sized = tester.widget<SizedBox>(
      find.descendant(
        of: find.byType(Center),
        matching: find.byType(SizedBox),
      ).first,
    );
    expect(sized.width, closeTo(200, 0.1));
    expect(sized.height, closeTo(200 / 1.5, 0.5));
  });

  testWidgets('buildRotatedCoverPreview no rotation uses contain FittedBox',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: buildRotatedCoverPreview(
            preview: const ColoredBox(color: Colors.red),
            effectiveQuarterTurns: 0,
            baseAspectRatio: 16 / 9,
          ),
        ),
      ),
    );
    expect(find.byType(FittedBox), findsOneWidget);
    expect(tester.widget<FittedBox>(find.byType(FittedBox)).fit, BoxFit.contain);
    expect(find.byType(RotatedBox), findsNothing);
  });

  testWidgets('buildRotatedCoverPreview with rotation adds RotatedBox',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: buildRotatedCoverPreview(
            preview: const ColoredBox(color: Colors.blue),
            effectiveQuarterTurns: 1,
            baseAspectRatio: 16 / 9,
            frameSize: const Size(1280, 720),
          ),
        ),
      ),
    );
    expect(find.byType(RotatedBox), findsOneWidget);
    expect(find.byType(FittedBox), findsOneWidget);
  });
}
