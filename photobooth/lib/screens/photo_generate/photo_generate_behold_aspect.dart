import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/print_orientation.dart';
import 'photo_generate_viewmodel.dart';

/// Portrait phone layout (same breakpoint as capture preview).
bool beholdCardIsPhonePortrait(BuildContext context) {
  return MediaQuery.orientationOf(context) == Orientation.portrait &&
      MediaQuery.sizeOf(context).shortestSide < 600;
}

/// Width/height for the BEHOLD single-result hero card.
///
/// Driven by [PhotoGenerateViewModel.printOrientation], which defaults from
/// session person count (solo → portrait, group → landscape) and can be toggled
/// on the BEHOLD screen for print.
double beholdSingleResultCardAspectRatio(
  BuildContext context,
  PhotoGenerateViewModel viewModel, {
  required double maxWidth,
  required double maxHeight,
}) {
  return viewModel.printOrientation.cardAspectRatio;
}

/// Width ÷ height of the generated/capture hero (defaults to 2:3 AI portrait).
double beholdHeroContentAspectRatio(PhotoGenerateViewModel viewModel) {
  final aspect = viewModel.beholdHeroAspectRatio;
  if (aspect != null && aspect.isFinite && aspect > 0) {
    return aspect;
  }
  return 2 / 3;
}

/// Landscape print preview with portrait art uses a centered mat instead of
/// stretching the photo to the wide card.
bool beholdUsesLandscapePrintMat({
  required PrintOrientation printOrientation,
  required double contentAspect,
}) {
  return printOrientation == PrintOrientation.landscape && contentAspect < 1.0;
}

/// Horizontal inset on a 6×4 print sheet when the art is portrait-shaped.
double beholdLandscapePrintMatHorizontalFraction(double contentAspect) {
  if (contentAspect >= 1.0) return 0;
  final portraitness = (1.0 - contentAspect).clamp(0.0, 0.6);
  return (0.08 + portraitness * 0.12).clamp(0.08, 0.18);
}

const double kBeholdLandscapePrintMatVerticalFraction = 0.06;

/// Sizes portrait art centered on a landscape print-preview card.
({double width, double height}) beholdLandscapePrintMatPhotoSize({
  required double cardWidth,
  required double cardHeight,
  required double contentAspect,
}) {
  final hPad =
      cardWidth * beholdLandscapePrintMatHorizontalFraction(contentAspect);
  final vPad = cardHeight * kBeholdLandscapePrintMatVerticalFraction;
  return fitBeholdHeroAspectInBox(
    maxWidth: math.max(1, cardWidth - 2 * hPad),
    maxHeight: math.max(1, cardHeight - 2 * vPad),
    aspect: contentAspect,
  );
}

/// Fits [aspect] inside a box without exceeding [maxWidth] or [maxHeight].
({double width, double height}) fitBeholdHeroAspectInBox({
  required double maxWidth,
  required double maxHeight,
  required double aspect,
}) {
  late double cardW;
  late double cardH;
  if (maxWidth / maxHeight > aspect) {
    cardH = maxHeight;
    cardW = cardH * aspect;
  } else {
    cardW = maxWidth;
    cardH = cardW / aspect;
  }
  return (width: cardW, height: cardH);
}

/// BEHOLD hero uses [BoxFit.contain] so portrait AI outputs are not cropped when
/// the print orientation card does not match the generated image aspect.
BoxFit beholdSingleResultHeroImageFit(PrintOrientation orientation) =>
    BoxFit.contain;
