import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:photobooth/screens/theme_slideshow/theme_slideshow_viewmodel.dart';
import 'package:photobooth/services/theme_manager.dart';

import '../fixtures/theme_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'kiosk_code': 'K1'});
  });

  test('getThemeForImageUrl matches normalized sample URL', () async {
    final tm = ThemeManager.forTesting(ThemesFakeApi([sampleTheme('t1')]));
    await tm.fetchThemes();
    final vm = ThemeSlideshowViewModel(themeManager: tm);
    await vm.fetchThemes();
    final url = vm.getSampleImageUrls().first;
    expect(vm.getThemeForImageUrl(url)?.id, 't1');
    expect(vm.getThemeForImageUrl(''), isNull);
    vm.dispose();
  });

  test('preloadImages with no themes clears state', () async {
    final tm = ThemeManager.forTesting(ThemesFakeApi([]));
    final vm = ThemeSlideshowViewModel(themeManager: tm);
    await vm.fetchThemes();
    expect(vm.getSampleImageUrls(), isEmpty);
    vm.dispose();
  });

  test('fetchThemes surfaces ApiException when no cache', () async {
    final tm = ThemeManager.forTesting(ThemesFakeApi([], throwOnFetch: true));
    final vm = ThemeSlideshowViewModel(themeManager: tm);
    await vm.fetchThemes();
    expect(vm.hasError, isTrue);
    vm.dispose();
  });
}
