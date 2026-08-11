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
    test('oversamples by device pixel ratio for sharp tablet strips', () {
      expect(
        flashbackLookPreviewCacheWidth(layoutWidth: 400, devicePixelRatio: 2),
        1000,
      );
      expect(
        flashbackLookPreviewCacheWidth(layoutWidth: 500, devicePixelRatio: 2.5),
        1280,
      );
    });

    test('clamps decode size for memory safety', () {
      expect(
        flashbackLookPreviewCacheWidth(layoutWidth: 80, devicePixelRatio: 1),
        640,
      );
      expect(
        flashbackLookPreviewCacheWidth(layoutWidth: 2000, devicePixelRatio: 3),
        1280,
      );
    });

    test('falls back when layout width is invalid', () {
      expect(
        flashbackLookPreviewCacheWidth(
          layoutWidth: double.nan,
          devicePixelRatio: 2,
        ),
        1280,
      );
    });
  });
}
