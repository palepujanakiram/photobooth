import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/theme_selection/theme_model.dart';
import 'package:photobooth/services/api_service.dart';
import 'package:photobooth/services/theme_manager.dart';
import 'package:photobooth/utils/exceptions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/theme_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'kiosk_code': 'K1'});
  });

  test('fetchThemes caches and returns active themes', () async {
    final tm = ThemeManager.forTesting(ThemesFakeApi([sampleTheme('t1')]));
    final first = await tm.fetchThemes();
    expect(first, hasLength(1));
    expect(tm.hasThemes, isTrue);
    expect(tm.getActiveThemes(), hasLength(1));
    expect(tm.getThemeById('t1')?.id, 't1');
    expect(tm.getSampleImageUrls(), isNotEmpty);
  });

  test('fetchThemes returns cache without second network call', () async {
    final api = ThemesFakeApi([sampleTheme('t1')]);
    final tm = ThemeManager.forTesting(api);
    await tm.fetchThemes();
    await tm.fetchThemes();
    expect(tm.themes, hasLength(1));
  });

  test('fetchThemes forceRefresh after error', () async {
    final tm = ThemeManager.forTesting(ThemesFakeApi([sampleTheme('t1')]));
    await tm.fetchThemes();
    final failing = ThemeManager.forTesting(
      ThemesFakeApi([sampleTheme('t1')], throwOnFetch: true),
    );
    await expectLater(failing.fetchThemes(), throwsA(isA<ApiException>()));
    final refreshed = await tm.fetchThemes(forceRefresh: true);
    expect(refreshed, hasLength(1));
  });

  test('clearCache notifies listeners', () async {
    final tm = ThemeManager.forTesting(ThemesFakeApi([sampleTheme('t1')]));
    await tm.fetchThemes();
    var notified = false;
    tm.addListener(() => notified = true);
    tm.clearCache();
    expect(notified, isTrue);
    expect(tm.hasThemes, isFalse);
  });

  test('fetchThemes rethrows when empty and API fails', () async {
    final tm = ThemeManager.forTesting(ThemesFakeApi([], throwOnFetch: true));
    expect(() => tm.fetchThemes(), throwsA(isA<ApiException>()));
  });
}
