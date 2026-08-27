import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/api_environment.dart';
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

  test('branch default API host is stage on offline builds', () {
    expect(AppConfig.branchDefaultEnvironment, ApiEnvironment.stage);
    expect(AppConfig.retrofitAnnotationBaseUrl, 'https://zenai.fly.dev');
  });

  test('share URL helpers use the configured base URL', () {
    expect(
      AppConfig.shareUrlForToken(' token-1 '),
      '${AppConfig.baseUrl}/s/token-1',
    );
    expect(
      AppConfig.shareLongUrlForToken('token-1'),
      '${AppConfig.baseUrl}/share/token-1',
    );
  });
}
