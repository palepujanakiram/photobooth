import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Which widget to put in the POSE preview slot.
enum CaptureLivePreviewKind {
  gallery,
  capturedStill,
  switchFreeze,
  sidecar,
  uvc,
  startingPlaceholder,
  pluginCamera,
}

/// Hold the last painted frame while the next camera session opens.
bool shouldShowCameraSwitchFreezeFrame({
  required bool hasFreezeFrame,
  required bool switchInProgress,
  required bool hasCapturedPhoto,
  required bool isSelectingFromGallery,
}) {
  return hasFreezeFrame &&
      switchInProgress &&
      !hasCapturedPhoto &&
      !isSelectingFromGallery;
}

/// Boundary that currently paints the live preview (plugin, UVC, or sidecar).
GlobalKey cameraSwitchFreezeBoundaryKey({
  required bool useSidecarPosePreview,
  required bool isUsingUvc,
  required GlobalKey sidecarKey,
  required GlobalKey uvcKey,
  required GlobalKey pluginKey,
}) {
  if (useSidecarPosePreview) return sidecarKey;
  if (isUsingUvc) return uvcKey;
  return pluginKey;
}

CaptureLivePreviewKind resolveCaptureLivePreviewKind({
  required bool isSelectingFromGallery,
  required bool hasCapturedPhoto,
  required bool showSwitchFreeze,
  required bool useSidecarPosePreview,
  required bool isUsingUvc,
  required bool hasCameraController,
}) {
  if (isSelectingFromGallery) return CaptureLivePreviewKind.gallery;
  if (hasCapturedPhoto) return CaptureLivePreviewKind.capturedStill;
  if (showSwitchFreeze) return CaptureLivePreviewKind.switchFreeze;
  if (useSidecarPosePreview) return CaptureLivePreviewKind.sidecar;
  if (isUsingUvc) return CaptureLivePreviewKind.uvc;
  if (!hasCameraController) return CaptureLivePreviewKind.startingPlaceholder;
  return CaptureLivePreviewKind.pluginCamera;
}

/// Last painted pixels of [boundaryKey]. Caller must [ui.Image.dispose].
Future<ui.Image?> captureRepaintBoundaryImage({
  required GlobalKey boundaryKey,
  int maxLongEdge = 720,
  Future<ui.Image> Function(RenderRepaintBoundary boundary, double pixelRatio)?
      captureImage,
}) async {
  final context = boundaryKey.currentContext;
  if (context == null) return null;
  final renderObject = context.findRenderObject();
  if (renderObject is! RenderRepaintBoundary) return null;
  if (!renderObject.hasSize || renderObject.size.isEmpty) return null;

  final longEdge = math.max(renderObject.size.width, renderObject.size.height);
  final pixelRatio = math.min(1.0, maxLongEdge / longEdge);
  try {
    final capture = captureImage ??
        (RenderRepaintBoundary boundary, double ratio) {
          return boundary.toImage(pixelRatio: ratio);
        };
    return await capture(renderObject, pixelRatio);
  } catch (_) {
    return null;
  }
}
