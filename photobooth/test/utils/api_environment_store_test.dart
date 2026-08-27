import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/api_environment_store.dart';
import 'package:photobooth/utils/api_environment.dart';
import 'package:photobooth/utils/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ApiEnvironmentStore.resetForTests();
  });

  group('apiEnvironmentFromStorage', () {
    test('parses live and stage aliases', () {
      expect(apiEnvironmentFromStorage('live'), ApiEnvironment.live);
      expect(apiEnvironmentFromStorage('STAGE'), ApiEnvironment.stage);
      expect(apiEnvironmentFromStorage('zenai'), ApiEnvironment.stage);
      expect(
        apiEnvironmentFromStorage('https://fotozenai.fly.dev'),
        ApiEnvironment.live,
      );
      expect(apiEnvironmentFromStorage('nope'), isNull);
    });
  });

  group('ApiEnvironmentStore', () {
    test('cold start forces Live even when prefs had Stage', () async {
      SharedPreferences.setMockInitialValues({
        ApiEnvironmentStore.prefsKey: 'stage',
      });
      await ApiEnvironmentStore.load();
      expect(ApiEnvironmentStore.current, ApiEnvironment.live);
      expect(AppConfig.baseUrl, 'https://fotozenai.fly.dev');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ApiEnvironmentStore.prefsKey), 'live');
    });

    test('defaults to live when prefs empty', () async {
      await ApiEnvironmentStore.load();
      expect(ApiEnvironmentStore.current, ApiEnvironment.live);
      expect(AppConfig.baseUrl, 'https://fotozenai.fly.dev');
    });

    test('set(stage) works for this process until next load', () async {
      await ApiEnvironmentStore.load();
      await ApiEnvironmentStore.set(ApiEnvironment.stage);
      expect(AppConfig.baseUrl, 'https://zenai.fly.dev');

      ApiEnvironmentStore.resetForTests();
      await ApiEnvironmentStore.load();
      expect(ApiEnvironmentStore.current, ApiEnvironment.live);
      expect(AppConfig.baseUrl, 'https://fotozenai.fly.dev');
    });
  });

  group('AppConfig bearer helpers', () {
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
  });
}
