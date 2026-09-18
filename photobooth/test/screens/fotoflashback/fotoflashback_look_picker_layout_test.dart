import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/fotoflashback/fotoflashback_look_picker_layout.dart';
import 'package:photobooth/utils/constants.dart';

void main() {
  group('flashbackLookPickerMaxContentWidth', () {
    test('phones keep historical 760 content column', () {
      expect(
        flashbackLookPickerMaxContentWidth(AppConstants.kTabletBreakpoint - 1),
        kFlashbackLookPickerMaxWidthPhone,
      );
      expect(flashbackLookPickerMaxContentWidth(390), 760);
    });

    test('tablets use wider column for ~11" landscape kiosks', () {
      expect(
        flashbackLookPickerMaxContentWidth(AppConstants.kTabletBreakpoint),
        kFlashbackLookPickerMaxWidthTablet,
      );
      expect(flashbackLookPickerMaxContentWidth(800), 1200);
    });
  });

  group('flashbackLookPreviewCacheWidth', () {
    test('oversamples by device pixel ratio then clamps for TV memory', () {
      expect(
        flashbackLookPreviewCacheWidth(layoutWidth: 400, devicePixelRatio: 2),
        kFlashbackLookPreviewCacheWidthMax,
      );
      expect(
        flashbackLookPreviewCacheWidth(layoutWidth: 500, devicePixelRatio: 2.5),
        kFlashbackLookPreviewCacheWidthMax,
      );
    });

    test('clamps decode size for memory safety', () {
      expect(
        flashbackLookPreviewCacheWidth(layoutWidth: 80, devicePixelRatio: 1),
        kFlashbackLookPreviewCacheWidthMin,
      );
      expect(
        flashbackLookPreviewCacheWidth(layoutWidth: 2000, devicePixelRatio: 3),
        kFlashbackLookPreviewCacheWidthMax,
      );
    });

    test('uses oversampled width when it sits between clamps', () {
      expect(
        flashbackLookPreviewCacheWidth(layoutWidth: 200, devicePixelRatio: 2),
        500,
      );
    });

    test('falls back when layout width is invalid', () {
      expect(
        flashbackLookPreviewCacheWidth(
          layoutWidth: double.nan,
          devicePixelRatio: 2,
        ),
        kFlashbackLookPreviewCacheWidthMax,
      );
      expect(
        flashbackLookPreviewCacheWidth(layoutWidth: 0, devicePixelRatio: 2),
        kFlashbackLookPreviewCacheWidthMax,
      );
    });

    test('falls back when device pixel ratio is invalid', () {
      expect(
        flashbackLookPreviewCacheWidth(
          layoutWidth: 200,
          devicePixelRatio: 0,
        ),
        500,
      );
    });
  });

  group('flashbackLookOverlayDecodeSize', () {
    test('caps the long edge of a tall strip overlay', () {
      final size = flashbackLookOverlayDecodeSize(
        layoutWidth: 200,
        layoutHeight: 600,
        devicePixelRatio: 2,
      );
      expect(size.cacheWidth, isNull);
      expect(size.cacheHeight, kFlashbackLookPreviewCacheWidthMax);
    });

    test('caps the long edge of a landscape 6x4 overlay', () {
      final size = flashbackLookOverlayDecodeSize(
        layoutWidth: 600,
        layoutHeight: 400,
        devicePixelRatio: 2,
      );
      expect(size.cacheWidth, kFlashbackLookPreviewCacheWidthMax);
      expect(size.cacheHeight, isNull);
    });
  });

  test('look preview uses medium filter quality to avoid high saveLayers', () {
    expect(
      kFlashbackLookPreviewFilterQuality,
      FilterQuality.medium,
    );
  });
}
