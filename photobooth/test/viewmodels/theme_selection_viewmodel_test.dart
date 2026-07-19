import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/theme_selection/theme_model.dart';
import 'package:photobooth/screens/theme_selection/theme_selection_viewmodel.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:photobooth/services/theme_manager.dart';
import 'package:photobooth/utils/constants.dart';
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

  test('themeCarouselAutoScroll defaults off and persists', () async {
    final vm = ThemeViewModel(apiService: FakeApiService());
    await vm.loadLayoutPreference();
    expect(vm.themeCarouselAutoScroll, isFalse);

    await vm.setThemeCarouselAutoScroll(true);
    expect(vm.themeCarouselAutoScroll, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool(AppConstants.kPrefsThemeCarouselAutoScroll),
      isTrue,
    );

    final vm2 = ThemeViewModel(apiService: FakeApiService());
    await vm2.loadLayoutPreference();
    expect(vm2.themeCarouselAutoScroll, isTrue);

    await vm2.toggleThemeCarouselAutoScroll();
    expect(vm2.themeCarouselAutoScroll, isFalse);

    vm.dispose();
    vm2.dispose();
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

  ThemeModel personTheme(
    String id, {
    bool? solo,
    bool? couple,
    bool? largeGroup,
  }) =>
      sampleTheme(id).copyWith((p) {
        p.applicableSolo = solo;
        p.applicableCouple = couple;
        p.applicableLargeGroup = largeGroup;
      });

  void bindSession(String id) {
    SessionManager().setSessionFromResponse({
      'id': id,
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': <dynamic>[],
      'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
    });
  }

  test('re-filters themes when person count changes for bound session',
      () async {
    final tm = ThemeManager.forTesting(ThemesFakeApi([
      personTheme('solo', solo: true, couple: false, largeGroup: false),
      personTheme('group', solo: false, couple: false, largeGroup: true),
    ]));
    await tm.fetchThemes();
    bindSession('sess-refilter');

    final vm = ThemeViewModel(themeManager: tm, apiService: FakeApiService());
    await vm.loadThemes();

    // Default count = 1 (solo) → only the solo theme is applicable.
    expect(vm.filteredThemes.map((t) => t.id), ['solo']);
    expect(vm.selectedTheme?.id, 'solo');

    var notified = 0;
    vm.addListener(() => notified++);

    // Authoritative count arrives (group of 3) → list re-filters + notifies.
    SessionManager().setPersonCount(3);
    expect(vm.filteredThemes.map((t) => t.id), ['group']);
    expect(vm.selectedTheme?.id, 'group');
    expect(notified, greaterThan(0));

    // Idempotent: same count does not change selection.
    vm.bindToCurrentSession();
    expect(vm.selectedTheme?.id, 'group');
    vm.dispose();
  });

  test('re-filter keeps current selection and drops stale armed theme',
      () async {
    final tm = ThemeManager.forTesting(ThemesFakeApi([
      personTheme('any', solo: true, couple: true, largeGroup: true),
      personTheme('soloOnly', solo: true, couple: false, largeGroup: false),
    ]));
    await tm.fetchThemes();
    bindSession('sess-keep');

    final vm = ThemeViewModel(themeManager: tm, apiService: FakeApiService());
    await vm.loadThemes();

    vm.setCarouselIndex(1);
    expect(vm.selectedTheme?.id, 'soloOnly');
    vm.armTheme(vm.filteredThemes[1]);
    expect(vm.armedTheme?.id, 'soloOnly');

    // Bump to a group: 'soloOnly' drops out, 'any' remains and is reselected.
    SessionManager().setPersonCount(3);
    expect(vm.filteredThemes.map((t) => t.id), ['any']);
    expect(vm.selectedTheme?.id, 'any');
    expect(vm.hasArmedTheme, isFalse);
    vm.dispose();
  });

  test('re-filter falls back to All category and clears when none applicable',
      () async {
    final tm = ThemeManager.forTesting(ThemesFakeApi([
      personTheme('solo', solo: true, couple: false, largeGroup: false)
          .copyWith((p) => p.categoryId = 'royal'),
    ]));
    await tm.fetchThemes();
    bindSession('sess-empty');

    final vm = ThemeViewModel(themeManager: tm, apiService: FakeApiService());
    await vm.loadThemes();
    vm.selectCategory('royal');
    expect(vm.filteredThemes.map((t) => t.id), ['solo']);

    // Group count: no theme applies at all → selection cleared, category resets.
    SessionManager().setPersonCount(3);
    expect(vm.filteredThemes, isEmpty);
    expect(vm.selectedTheme, isNull);
    vm.dispose();
  });

  test('resetForNewCustomer clears armed theme when session changes', () async {
    final tm = ThemeManager.forTesting(ThemesFakeApi([
      sampleTheme('t1'),
      sampleTheme('t2'),
    ]));
    await tm.fetchThemes();
    final vm = ThemeViewModel(themeManager: tm, apiService: FakeApiService());
    await vm.loadThemes();
    vm.armTheme(vm.themes[1]);
    expect(vm.armedTheme?.id, 't2');

    SessionManager().setSessionFromResponse({
      'id': 'sess-new',
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': <dynamic>[],
      'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
    });

    expect(vm.hasArmedTheme, isFalse);
    expect(vm.selectedTheme?.id, 't1');
    expect(vm.carouselIndex, 0);
    vm.dispose();
  });
}
