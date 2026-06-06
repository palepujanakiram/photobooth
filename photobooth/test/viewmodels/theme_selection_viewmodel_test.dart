import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/theme_selection/theme_selection_viewmodel.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:photobooth/services/theme_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_api_service.dart';
import '../fixtures/theme_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SessionManager().clearSession();
  });

  test('category helpers and selection', () async {
    final tm = ThemeManager.forTesting(ThemesFakeApi([
      sampleTheme('t1').copyWith((p) {
        p.categoryId = 'royal';
        p.categoryName = 'Royal';
      }),
      sampleTheme('t2').copyWith((p) => p.categoryId = 'wedding'),
    ]));
    await tm.fetchThemes();
    final vm = ThemeViewModel(themeManager: tm, apiService: FakeApiService());
    await vm.loadThemes();
    expect(vm.categoryIds, contains('royal'));
    expect(vm.getCategoryDisplayName('royal'), 'Royal');
    vm.selectCategory('royal');
    expect(vm.filteredThemes, hasLength(1));
    vm.selectTheme(vm.filteredThemes.first);
    expect(vm.selectedTheme?.id, 't1');
    vm.armTheme(vm.filteredThemes.first);
    expect(vm.hasArmedTheme, isTrue);
    vm.clearArmedTheme();
    expect(vm.hasArmedTheme, isFalse);
    vm.dispose();
  });

  test('loadLayoutPreference defaults false', () async {
    final vm = ThemeViewModel(apiService: FakeApiService());
    await vm.loadLayoutPreference();
    expect(vm.useCardGridLayout, isFalse);
    await vm.setUseCardGridLayout(true);
    expect(vm.useCardGridLayout, isTrue);
    vm.dispose();
  });

  test('updateSessionWithTheme requires session', () async {
    final tm = ThemeManager.forTesting(ThemesFakeApi([sampleTheme('t1')]));
    await tm.fetchThemes();
    final vm = ThemeViewModel(themeManager: tm, apiService: FakeApiService());
    await vm.loadThemes();
    vm.selectTheme(vm.themes.first);
    final ok = await vm.updateSessionWithTheme();
    expect(ok, isFalse);
    vm.dispose();
  });
}
