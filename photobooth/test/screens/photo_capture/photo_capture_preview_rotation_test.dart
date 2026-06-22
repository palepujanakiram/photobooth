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
}
