import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/theme_selection/theme_model.dart';
import 'package:photobooth/utils/theme_filter.dart';

ThemeModel _theme({
  required String id,
  bool? isActive,
  bool? solo,
  bool? couple,
  bool? small,
  bool? large,
}) {
  return ThemeModel(
    id: id,
    categoryId: 'fantasy',
    name: id,
    description: '',
    promptText: '',
    isActive: isActive,
    applicableSolo: solo,
    applicableCouple: couple,
    applicableSmallGroup: small,
    applicableLargeGroup: large,
  );
}

void main() {
  group('ThemeFilter', () {
    test('solo-only theme hidden for 3 people', () {
      final dragonsRealm = _theme(
        id: 'dragons',
        isActive: true,
        solo: true,
        couple: false,
        small: false,
        large: false,
      );
      expect(ThemeFilter.showTheme(dragonsRealm, 3), isFalse);
      expect(
        ThemeFilter.filterForPersonCount([dragonsRealm], 3),
        isEmpty,
      );
    });

    test('solo theme shown for 1 person', () {
      final solo = _theme(id: 'solo', isActive: true, solo: true, large: false);
      expect(ThemeFilter.showTheme(solo, 1), isTrue);
    });

    test('legacy smallGroup fallback for solo when applicableSolo null', () {
      final legacy = _theme(
        id: 'legacy',
        isActive: true,
        solo: null,
        small: true,
        large: false,
      );
      expect(ThemeFilter.showTheme(legacy, 1), isTrue);
      expect(ThemeFilter.showTheme(legacy, 3), isFalse);
    });

    test('couple theme uses smallGroup fallback', () {
      final couple = _theme(
        id: 'c',
        isActive: true,
        couple: null,
        small: true,
        large: false,
      );
      expect(ThemeFilter.showTheme(couple, 2), isTrue);
      expect(ThemeFilter.showTheme(couple, 3), isFalse);
    });

    test('large group theme for 3+', () {
      final group = _theme(
        id: 'g',
        isActive: true,
        solo: false,
        large: true,
      );
      expect(ThemeFilter.showTheme(group, 3), isTrue);
      expect(ThemeFilter.showTheme(group, 1), isFalse);
    });

    test('defaults personCount to 1 when null', () {
      final solo = _theme(id: 's', isActive: true, solo: true, large: false);
      expect(ThemeFilter.showTheme(solo, null), isTrue);
    });
  });
}
