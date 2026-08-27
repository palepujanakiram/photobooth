import 'package:flutter_test/flutter_test.dart';

import 'package:photobooth/utils/app_strings.dart';
import 'package:photobooth/utils/classic_shot_choice_options.dart';
import 'package:photobooth/utils/classic_shot_mode.dart';

void main() {
  group('classicShotChoiceUsesPreviewScreen', () {
    test('true when more than one mode is enabled', () {
      expect(classicShotChoiceUsesPreviewScreen(const [3, 4]), isTrue);
      expect(classicShotChoiceUsesPreviewScreen(const [1, 3, 4]), isTrue);
    });

    test('false for a single enabled mode', () {
      expect(classicShotChoiceUsesPreviewScreen(const [4]), isFalse);
      expect(classicShotChoiceUsesPreviewScreen(const []), isFalse);
    });
  });

  group('classicShotChoiceOptions', () {
    test('orders 4 then 3 then 1 with distinct preview assets', () {
      final options = classicShotChoiceOptions(const [1, 3, 4]);
      expect(options, hasLength(3));
      expect(options.map((o) => o.mode), [
        ClassicShotMode.fourShot,
        ClassicShotMode.threeShot,
        ClassicShotMode.single6x4,
      ]);
      expect(options[0].previewAsset, AppStrings.experienceClassicPreviewAsset);
      expect(
        options[1].previewAsset,
        AppStrings.experienceClassicThreeShotPreviewAsset,
      );
      expect(
        options[2].previewAsset,
        AppStrings.experienceClassicOneShotPreviewAsset,
      );
    });

    test('omits disabled modes', () {
      final options = classicShotChoiceOptions(const [3, 4]);
      expect(options.map((o) => o.mode.shotCount), [4, 3]);
    });
  });
}
