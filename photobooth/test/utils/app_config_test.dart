import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/app_config.dart';

void main() {
  test('authorizationBearerHeader empty when token blank', () {
    expect(AppConfig.bearerHeaderForToken(''), isEmpty);
    expect(AppConfig.bearerHeaderForToken('   '), isEmpty);
    expect(AppConfig.authorizationBearerHeader, isEmpty);
  });

  test('bearerHeaderForToken includes Authorization when set', () {
    expect(
      AppConfig.bearerHeaderForToken('test-jwt'),
      {'Authorization': 'Bearer test-jwt'},
    );
  });
}
