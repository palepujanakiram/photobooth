import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/models/strip_models.dart';

void main() {
  test('parses enableOsdScrub from photoStripConfig', () {
    final model = AppSettingsModel.fromJson({
      'photoStripConfig': {'enableOsdScrub': true},
    });
    expect(model.enableOsdScrub, isTrue);
  });

  test('defaults enableOsdScrub when omitted', () {
    final model = AppSettingsModel.fromJson({});
    expect(model.enableOsdScrub, isNull);
  });

  test('parses enableSurpriseMeAi from photoStripConfig', () {
    final model = AppSettingsModel.fromJson({
      'photoStripConfig': {'enableSurpriseMeAi': true},
    });
    expect(model.enableSurpriseMeAi, isTrue);
  });

  test('defaults enableSurpriseMeAi when omitted', () {
    final model = AppSettingsModel.fromJson({});
    expect(model.enableSurpriseMeAi, isNull);
  });

  test('StripFiltersCatalog parses features.enableSurpriseMeAi', () {
    final catalog = StripFiltersCatalog.fromJson({
      'brand': 'FotoFlashback',
      'shotCount': 4,
      'filters': const [],
      'features': {
        'enableSurpriseMeAi': true,
        'enableOsdScrub': true,
      },
    });
    expect(catalog.enableSurpriseMeAi, isTrue);
    expect(catalog.enableOsdScrub, isTrue);
  });
}
