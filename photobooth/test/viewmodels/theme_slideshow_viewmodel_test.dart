import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:photobooth/screens/theme_slideshow/theme_slideshow_viewmodel.dart';
import 'package:photobooth/services/theme_manager.dart';
import 'package:photobooth/utils/theme_image_urls.dart';

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
    final themeUrl = resolveThemeSampleImageUrl(
      tm.themes.first.sampleImageUrl!,
    );
    expect(vm.getThemeForImageUrl(themeUrl)?.id, 't1');
    expect(vm.getThemeForImageUrl(''), isNull);
    vm.dispose();
  });

  test('getSampleImageUrls uses bundled slideshow assets', () {
    final vm = ThemeSlideshowViewModel(
      themeManager: ThemeManager.forTesting(ThemesFakeApi([])),
    );
    final urls = vm.getSampleImageUrls();
    expect(urls, isNotEmpty);
    expect(urls.first, startsWith('assets/slideshow/'));
    vm.dispose();
  });

  test('fetchThemes prefetch failure does not block slideshow assets', () async {
    final tm = ThemeManager.forTesting(ThemesFakeApi([], throwOnFetch: true));
    final vm = ThemeSlideshowViewModel(themeManager: tm);
    await vm.fetchThemes();
    expect(vm.hasError, isFalse);
    expect(vm.getSampleImageUrls(), isNotEmpty);
    vm.dispose();
  });

  test('dispose unsubscribes ThemeManager listener', () async {
    final tm = ThemeManager.forTesting(ThemesFakeApi([sampleTheme('t1')]));
    var vmUpdatesAfterDispose = 0;
    final vm = ThemeSlideshowViewModel(themeManager: tm);
    vm.addListener(() => vmUpdatesAfterDispose++);
    vm.dispose();
    await tm.fetchThemes(forceRefresh: true);
    expect(vmUpdatesAfterDispose, 0);
  });
}
