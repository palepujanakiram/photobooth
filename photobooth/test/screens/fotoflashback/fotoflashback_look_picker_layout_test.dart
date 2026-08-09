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
}
