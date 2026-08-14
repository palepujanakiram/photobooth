import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../../utils/print_orientation.dart';
import 'photo_capture_viewmodel.dart';

bool captureCardIsPhonePortrait(BuildContext context) {
  return MediaQuery.orientationOf(context) == Orientation.portrait &&
      MediaQuery.sizeOf(context).shortestSide < AppConstants.kTabletBreakpoint;
}

/// Aspect that fills [layoutConstraints] (portrait phones clamp to a tall slot;
/// landscape may use the full pane ratio so the card scales with orientation).
double captureCardViewportSlotAspect(
  BoxConstraints layoutConstraints,
  double fallbackAspect, {
  bool allowLandscape = false,
}) {
  final w = layoutConstraints.maxWidth;
  final h = layoutConstraints.maxHeight;
  if (w <= 0 || h <= 0) return fallbackAspect;
  if (allowLandscape) {
    // Prefer ~16:9 POSE cards; avoid ultra-wide viewport strips on short panes.
    return (w / h).clamp(1.15, 16 / 9);
  }
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
  final locked = viewModel.lockedCaptureCardAspectRatio;
  if (locked != null && locked > 0) {
    return locked.clamp(0.35, 2.85);
  }
  final isLandscape =
      MediaQuery.orientationOf(context) == Orientation.landscape;
  // Portrait Classic: keep the print-style theme slot. Landscape: scale to the
  // still / feed so tablets are not stuck with a narrow portrait tower.
  if (preferThemeSlotAspect && !isLandscape) {
    if (captureCardIsPhonePortrait(context)) {
      return captureCardViewportSlotAspect(layoutConstraints, fallbackAspect);
    }
    return fallbackAspect;
  }
  final decodedAspect = captureCardDecodedImageAspect(
    viewModel.capturedImagePixelSize,
  );
  if (decodedAspect != null) return decodedAspect;
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
  if (isLandscape) {
    return captureCardViewportSlotAspect(
      layoutConstraints,
      fallbackAspect,
      allowLandscape: true,
    );
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
  final isLandscape =
      MediaQuery.orientationOf(context) == Orientation.landscape;
  // Portrait Classic: theme slot. Landscape: follow the live feed / pane so the
  // preview card scales with orientation instead of a fixed portrait tower.
  if (preferThemeSlotAspect && !isLandscape) {
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
  if (isLandscape) {
    return captureCardViewportSlotAspect(
      layoutConstraints,
      fallbackAspect,
      allowLandscape: true,
    );
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
