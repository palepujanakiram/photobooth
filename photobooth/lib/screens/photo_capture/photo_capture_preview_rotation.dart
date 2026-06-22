import 'package:flutter/material.dart';

/// Auto-rotation for live preview in 90° steps (0–3).
///
/// USB / HDMI capture feeds are already upright on kiosk tablets; skip the
/// Android TV / sensor-orientation workaround for those devices.
int previewAutoQuarterTurnsForSensor({
  required bool applyAndroidRotationWorkaround,
  required int sensorOrientationDegrees,
  required bool isFrontCamera,
  required bool isExternalFeed,
  required int displayRotationIndex,
}) {
  if (!applyAndroidRotationWorkaround || isExternalFeed) return 0;

  final surfaceRotationDegrees = switch (displayRotationIndex) {
    1 => 90,
    2 => 180,
    3 => 270,
    _ => 0,
  };

  final rotationDegrees = isFrontCamera
      ? (sensorOrientationDegrees + surfaceRotationDegrees) % 360
      : (sensorOrientationDegrees - surfaceRotationDegrees + 360) % 360;

  return ((360 - rotationDegrees) % 360) ~/ 90;
}

/// Display width/height for a preview after [effectiveQuarterTurns] rotation.
(double, double) previewDisplayDimensions({
  required Size? previewSize,
  required int effectiveQuarterTurns,
  required double displayAspectRatio,
}) {
  final odd = effectiveQuarterTurns.isOdd;
  if (previewSize == null) {
    return odd ? (1.0, displayAspectRatio) : (displayAspectRatio, 1.0);
  }
  return odd
      ? (previewSize.height, previewSize.width)
      : (previewSize.width, previewSize.height);
}

/// Full-bleed rotated camera preview (built-in CameraX or UVC texture).
Widget buildRotatedCoverPreview({
  required Widget preview,
  required int effectiveQuarterTurns,
  required double baseAspectRatio,
  Size? frameSize,
}) {
  Widget rotated = preview;
  if (effectiveQuarterTurns != 0) {
    rotated = RotatedBox(
      quarterTurns: effectiveQuarterTurns,
      child: rotated,
    );
  }

  final displayAspectRatio =
      effectiveQuarterTurns.isOdd ? 1 / baseAspectRatio : baseAspectRatio;
  final (width, height) = previewDisplayDimensions(
    previewSize: frameSize,
    effectiveQuarterTurns: effectiveQuarterTurns,
    displayAspectRatio: displayAspectRatio,
  );

  return ClipRect(
    child: SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        alignment: Alignment.center,
        child: SizedBox(
          width: width,
          height: height,
          child: AspectRatio(
            aspectRatio: displayAspectRatio,
            child: rotated,
          ),
        ),
      ),
    ),
  );
}
