import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../../utils/print_orientation.dart';
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

double? captureCardDecodedImageAspect(Size? pixels) {
  if (pixels == null || pixels.height <= 0) return null;
  return (pixels.width / pixels.height).clamp(0.35, 2.85);
}

/// Groups of 3+ print landscape — use that frame on POSE review before pixels decode.
double? captureCardAspectRatioFromPersonCount(int? personCount) {
  if (personCount == null || personCount <= 0) return null;
  final orientation = PrintOrientation.fromPersonCount(personCount);
  if (orientation == PrintOrientation.landscape) {
    return orientation.cardAspectRatio;
  }
  return null;
}

double captureCardAspectRatioForCaptured({
  required BuildContext context,
  required CaptureViewModel viewModel,
  required double fallbackAspect,
  required BoxConstraints layoutConstraints,
  bool preferThemeSlotAspect = false,
}) {
  // Prefer the still we actually captured. Sidecar live pose uses a portrait
  // theme slot; Canon JPEGs are landscape — a live lock would letterbox black.
  final decodedAspect = captureCardDecodedImageAspect(
    viewModel.capturedImagePixelSize,
  );
  if (decodedAspect != null) return decodedAspect;
  final locked = viewModel.lockedCaptureCardAspectRatio;
  if (locked != null && locked > 0) {
    return locked.clamp(0.35, 2.85);
  }
  // Pi USB MJPEG / theme-slot pose: keep the Classic portrait card on review
  // instead of flipping to landscape from person-count heuristics.
  if (preferThemeSlotAspect) {
    if (captureCardIsPhonePortrait(context)) {
      return captureCardViewportSlotAspect(layoutConstraints, fallbackAspect);
    }
    return fallbackAspect;
  }
  final personAspect = captureCardAspectRatioFromPersonCount(
    viewModel.estimatedPersonCountForCaptureReview,
  );
  if (personAspect != null) return personAspect;
  final isGalleryStill = viewModel.capturedPhoto?.cameraId == 'gallery';
  final liveAspect = isGalleryStill
      ? null
      : captureCardLivePreviewAspectRatio(viewModel);
  if (liveAspect != null) return liveAspect;
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
  bool preferThemeSlotAspect = false,
}) {
  // Sidecar Classic/AI pose uses the portrait theme slot (cover-crop the feed),
  // not the landscape HDMI/UVC buffer aspect.
  if (preferThemeSlotAspect) {
    if (captureCardIsPhonePortrait(context)) {
      return captureCardViewportSlotAspect(layoutConstraints, fallbackAspect);
    }
    return fallbackAspect;
  }
  // Portrait phones: always a portrait card. UVC/CameraX buffers are often
  // landscape while the guest holds the phone upright — do not inset a
  // landscape letterbox (Classic "Classic print" countdown looked wrong).
  if (captureCardIsPhonePortrait(context)) {
    return captureCardViewportSlotAspect(layoutConstraints, fallbackAspect);
  }
  if (uvcPreviewDisplaySize != null && uvcPreviewDisplaySize.height > 0) {
    return (uvcPreviewDisplaySize.width / uvcPreviewDisplaySize.height)
        .clamp(0.35, 2.85);
  }
  final liveAspect = captureCardLivePreviewAspectRatio(viewModel);
  if (liveAspect != null) return liveAspect;
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
  bool preferThemeSlotAspect = false,
}) {
  if (hasCapturedPhoto) {
    return captureCardAspectRatioForCaptured(
      context: context,
      viewModel: viewModel,
      fallbackAspect: fallbackAspect,
      layoutConstraints: layoutConstraints,
      preferThemeSlotAspect: preferThemeSlotAspect,
    );
  }
  return captureCardAspectRatioForLivePreview(
    context: context,
    viewModel: viewModel,
    fallbackAspect: fallbackAspect,
    layoutConstraints: layoutConstraints,
    uvcPreviewDisplaySize: uvcPreviewDisplaySize,
    preferThemeSlotAspect: preferThemeSlotAspect,
  );
}
