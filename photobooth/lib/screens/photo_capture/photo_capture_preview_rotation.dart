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

/// Same aspect rule as Flutter's [CameraPreview]: invert sensor ratio in portrait UI.
double cameraPreviewDisplayAspectRatio({
  required double controllerAspectRatio,
  required bool isLandscapeUi,
}) {
  if (controllerAspectRatio <= 0) return 1.0;
  return isLandscapeUi
      ? controllerAspectRatio
      : 1 / controllerAspectRatio;
}

/// Full-bleed cover for [CameraPreview] (or any child that already owns aspect).
///
/// Do **not** wrap [CameraPreview] in another sensor-[AspectRatio] — that fights
/// CameraPreview's portrait invert and squashes the texture on phones.
Widget buildCoverCameraPreview({
  required Widget cameraPreview,
  required double displayAspectRatio,
}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final parentW = constraints.maxWidth;
      final parentH = constraints.maxHeight;
      if (parentW <= 0 || parentH <= 0 || displayAspectRatio <= 0) {
        return cameraPreview;
      }

      late final double childW;
      late final double childH;
      if (parentW / parentH > displayAspectRatio) {
        childW = parentW;
        childH = childW / displayAspectRatio;
      } else {
        childH = parentH;
        childW = childH * displayAspectRatio;
      }

      return ClipRect(
        child: OverflowBox(
          minWidth: childW,
          maxWidth: childW,
          minHeight: childH,
          maxHeight: childH,
          alignment: Alignment.center,
          child: SizedBox(
            width: childW,
            height: childH,
            child: cameraPreview,
          ),
        ),
      );
    },
  );
}

/// Full-bleed rotated camera preview for raw textures (UVC / manual rotation).
///
/// Prefer [buildCoverCameraPreview] when the child is Flutter's [CameraPreview].
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
