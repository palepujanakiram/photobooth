import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import 'photo_capture_viewmodel.dart';

bool captureCardIsPhonePortrait(BuildContext context) {
  return MediaQuery.orientationOf(context) == Orientation.portrait &&
      MediaQuery.sizeOf(context).shortestSide < AppConstants.kTabletBreakpoint;
}

double captureCardViewportSlotAspect(
  BoxConstraints layoutConstraints,
  double fallbackAspect,
) {
  final w = layoutConstraints.maxWidth;
  final h = layoutConstraints.maxHeight;
  if (w <= 0 || h <= 0) return fallbackAspect;
  return (w / h).clamp(0.28, 0.92);
}

double? captureCardLivePreviewAspectRatio(CaptureViewModel viewModel) {
  final live = viewModel.previewDisplaySizeForCard;
  if (live != null && live.height > 0) {
    return (live.width / live.height).clamp(0.35, 2.85);
  }
  return null;
}

double captureCardAspectRatioForCaptured({
  required BuildContext context,
  required CaptureViewModel viewModel,
  required double fallbackAspect,
  required BoxConstraints layoutConstraints,
}) {
  final locked = viewModel.lockedCaptureCardAspectRatio;
  if (locked != null && locked > 0) {
    return locked.clamp(0.35, 2.85);
  }
  final liveAspect = captureCardLivePreviewAspectRatio(viewModel);
  if (liveAspect != null) return liveAspect;
  final pixels = viewModel.capturedImagePixelSize;
  if (pixels != null && pixels.height > 0) {
    return (pixels.width / pixels.height).clamp(0.35, 2.85);
  }
  if (captureCardIsPhonePortrait(context)) {
    return captureCardViewportSlotAspect(layoutConstraints, fallbackAspect);
  }
  return fallbackAspect;
}

double captureCardAspectRatioForLivePreview({
  required BuildContext context,
  required CaptureViewModel viewModel,
  required double fallbackAspect,
  required BoxConstraints layoutConstraints,
  Size? uvcPreviewDisplaySize,
}) {
  if (uvcPreviewDisplaySize != null && uvcPreviewDisplaySize.height > 0) {
    return (uvcPreviewDisplaySize.width / uvcPreviewDisplaySize.height)
        .clamp(0.35, 2.85);
  }
  final previewSize = viewModel.cameraController?.value.previewSize;
  final liveAspect = captureCardLivePreviewAspectRatio(viewModel);
  if (liveAspect != null) {
    if (captureCardIsPhonePortrait(context) && previewSize == null) {
      return captureCardViewportSlotAspect(layoutConstraints, fallbackAspect);
    }
    return liveAspect;
  }
  if (captureCardIsPhonePortrait(context)) {
    return captureCardViewportSlotAspect(layoutConstraints, fallbackAspect);
  }
  return fallbackAspect;
}

/// Width/height ratio for the capture card (decoded still, live preview, or fallback).
double captureCardAspectRatio(
  BuildContext context,
  CaptureViewModel viewModel,
  bool hasCapturedPhoto,
  double fallbackAspect,
  BoxConstraints layoutConstraints, {
  Size? uvcPreviewDisplaySize,
}) {
  if (hasCapturedPhoto) {
    return captureCardAspectRatioForCaptured(
      context: context,
      viewModel: viewModel,
      fallbackAspect: fallbackAspect,
      layoutConstraints: layoutConstraints,
    );
  }
  return captureCardAspectRatioForLivePreview(
    context: context,
    viewModel: viewModel,
    fallbackAspect: fallbackAspect,
    layoutConstraints: layoutConstraints,
    uvcPreviewDisplaySize: uvcPreviewDisplaySize,
  );
}
