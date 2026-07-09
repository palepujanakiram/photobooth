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

/// BEHOLD hero uses [BoxFit.contain] so portrait AI outputs are not cropped when
/// the print orientation card does not match the generated image aspect.
BoxFit beholdSingleResultHeroImageFit(PrintOrientation orientation) =>
    BoxFit.contain;
