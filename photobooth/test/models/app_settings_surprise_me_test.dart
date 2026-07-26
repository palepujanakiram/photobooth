import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';

void main() {
  test('parses enableSurpriseMeAi from photoStripConfig', () {
    final model = AppSettingsModel.fromJson({
      'photoStripConfig': {'enableSurpriseMeAi': true},
    });
    expect(model.enableSurpriseMeAi, isTrue);
  });

  test('parses enableOsdScrub from photoStripConfig', () {
    final model = AppSettingsModel.fromJson({
      'photoStripConfig': {'enableOsdScrub': true},
    });
    expect(model.enableOsdScrub, isTrue);
  });

  test('defaults enableSurpriseMeAi when omitted', () {
    final model = AppSettingsModel.fromJson({});
    expect(model.enableSurpriseMeAi, isNull);
    expect(model.enableOsdScrub, isNull);
  });
}
