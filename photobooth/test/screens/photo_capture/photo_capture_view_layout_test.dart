import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_view_layout.dart';
import 'package:photobooth/utils/constants.dart';

void main() {
  test('capturePreviewCardSizeFractions landscape vs portrait phone', () {
    final landscape = capturePreviewCardSizeFractions(
      isLandscape: true,
      isPhonePortrait: false,
    );
    expect(landscape.$1, AppConstants.kCapturePreviewCardMaxWidthFractionLandscape);
    expect(landscape.$2, AppConstants.kCapturePreviewCardMaxHeightFractionLandscape);

    final phonePortrait = capturePreviewCardSizeFractions(
      isLandscape: false,
      isPhonePortrait: true,
    );
    expect(phonePortrait.$2, AppConstants.kCapturePreviewCardMaxHeightFractionPhonePortrait);

    final tabletPortrait = capturePreviewCardSizeFractions(
      isLandscape: false,
      isPhonePortrait: false,
    );
    expect(tabletPortrait.$2, AppConstants.kCapturePreviewCardMaxHeightFractionPortrait);
  });

  test('capturePreviewCardDimensions fits aspect inside constraints', () {
    const constraints = BoxConstraints(maxWidth: 400, maxHeight: 300);
    final tall = capturePreviewCardDimensions(
      constraints: constraints,
      aspect: 16 / 9,
      maxW: 200,
      maxH: 150,
    );
    expect(tall.$1, lessThanOrEqualTo(400));
    expect(tall.$2, lessThanOrEqualTo(300));
    expect(tall.$1 / tall.$2, closeTo(16 / 9, 0.01));

    final wide = capturePreviewCardDimensions(
      constraints: constraints,
      aspect: 0.5,
      maxW: 300,
      maxH: 100,
    );
    expect(wide.$1, lessThanOrEqualTo(300));
    expect(wide.$2, lessThanOrEqualTo(100));
  });
}
