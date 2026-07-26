import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';

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
}
