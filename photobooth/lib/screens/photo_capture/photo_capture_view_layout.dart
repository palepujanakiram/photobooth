import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/constants.dart';

/// Max width/height fractions for the capture preview card (portrait vs landscape).
(double widthFrac, double heightFrac) capturePreviewCardSizeFractions({
  required bool isLandscape,
  required bool isPhonePortrait,
}) {
  final widthFrac = isLandscape
      ? AppConstants.kCapturePreviewCardMaxWidthFractionLandscape
      : AppConstants.kCapturePreviewCardMaxWidthFractionPortrait;
  final heightFrac = isLandscape
      ? AppConstants.kCapturePreviewCardMaxHeightFractionLandscape
      : (isPhonePortrait
          ? AppConstants.kCapturePreviewCardMaxHeightFractionPhonePortrait
          : AppConstants.kCapturePreviewCardMaxHeightFractionPortrait);
  return (widthFrac, heightFrac);
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
