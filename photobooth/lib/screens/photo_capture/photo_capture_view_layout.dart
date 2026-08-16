import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/constants.dart';

/// Max width for Retake / Take shot (and related) action columns.
const double kCaptureActionsMaxWidth = 360;

/// Max width/height fractions for the capture preview card (portrait vs landscape).
(double widthFrac, double heightFrac) capturePreviewCardSizeFractions({
  required bool isLandscape,
  required bool isPhonePortrait,
}) {
  final widthFrac = isLandscape
      ? AppConstants.kCapturePreviewCardMaxWidthFractionLandscape
      : AppConstants.kCapturePreviewCardMaxWidthFractionPortrait;
  final double heightFrac;
  if (isLandscape) {
    heightFrac = AppConstants.kCapturePreviewCardMaxHeightFractionLandscape;
  } else if (isPhonePortrait) {
    heightFrac = AppConstants.kCapturePreviewCardMaxHeightFractionPhonePortrait;
  } else {
    heightFrac = AppConstants.kCapturePreviewCardMaxHeightFractionPortrait;
  }
  return (widthFrac, heightFrac);
}

/// Max width/height for the POSE preview card inside [constraints].
///
/// Uses screen fractions on every form factor, then absolute landscape caps so
/// 32" / TV kiosks match the tablet FotoZen POSE card scale.
(double maxW, double maxH) capturePreviewCardMaxBounds({
  required Size media,
  required BoxConstraints constraints,
  required bool isLandscape,
  required bool isPhonePortrait,
}) {
  final (widthFrac, heightFrac) = capturePreviewCardSizeFractions(
    isLandscape: isLandscape,
    isPhonePortrait: isPhonePortrait,
  );
  var maxW = math.min(constraints.maxWidth, media.width * widthFrac);
  var maxH = math.min(constraints.maxHeight, media.height * heightFrac);
  if (isLandscape) {
    maxW = math.min(maxW, AppConstants.kCapturePreviewCardMaxWidthLandscape);
    maxH = math.min(maxH, AppConstants.kCapturePreviewCardMaxHeightLandscape);
  }
  return (maxW, maxH);
}

/// Computes preview card width/height inside [constraints] for [aspect].
(double cardW, double cardH) capturePreviewCardDimensions({
  required BoxConstraints constraints,
  required double aspect,
  required double maxW,
  required double maxH,
}) {
  late double cardW;
  late double cardH;
  if (maxW / maxH > aspect) {
    cardH = maxH;
    cardW = cardH * aspect;
  } else {
    cardW = maxW;
    cardH = cardW / aspect;
  }
  cardW = math.min(cardW, constraints.maxWidth);
  cardH = math.min(cardH, constraints.maxHeight);
  return (cardW, cardH);
}
