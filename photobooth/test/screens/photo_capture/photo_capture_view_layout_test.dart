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

  test('capturePreviewCardMaxBounds caps 32\" to tablet FotoZen scale', () {
    const padConstraints = BoxConstraints(maxWidth: 1200, maxHeight: 560);
    final pad = capturePreviewCardMaxBounds(
      media: const Size(1280, 800),
      constraints: padConstraints,
      isLandscape: true,
      isPhonePortrait: false,
    );
    expect(pad.$1, lessThanOrEqualTo(AppConstants.kCapturePreviewCardMaxWidthLandscape));
    expect(pad.$2, lessThanOrEqualTo(AppConstants.kCapturePreviewCardMaxHeightLandscape));
    expect(
      pad.$1,
      closeTo(1280 * AppConstants.kCapturePreviewCardMaxWidthFractionLandscape, 0.5),
    );

    const tvConstraints = BoxConstraints(maxWidth: 1840, maxHeight: 820);
    final tv = capturePreviewCardMaxBounds(
      media: const Size(1920, 1080),
      constraints: tvConstraints,
      isLandscape: true,
      isPhonePortrait: false,
    );
    expect(tv.$1, AppConstants.kCapturePreviewCardMaxWidthLandscape);
    expect(tv.$2, AppConstants.kCapturePreviewCardMaxHeightLandscape);
    // 32\" must not grow past the Pad-era absolute ceiling.
    expect(tv.$1, lessThanOrEqualTo(padConstraints.maxWidth));
  });
}
