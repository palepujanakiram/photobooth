import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/staff/staff_theme_controller.dart';
import 'package:photobooth/screens/staff/staff_theme_shell.dart';
import 'package:photobooth/utils/app_strings.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('StaffThemeController', () {
    test('defaults to dark and persists toggle', () async {
      final ctrl = StaffThemeController();
      expect(ctrl.isDark, isTrue);

      await ctrl.load();
      expect(ctrl.isDark, isTrue);
      expect(ctrl.isLoaded, isTrue);

      await ctrl.toggle();
      expect(ctrl.isDark, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(StaffThemeController.prefsKey), isFalse);

      final restored = StaffThemeController();
      await restored.load();
      expect(restored.isDark, isFalse);
    });

    test('load restores previously saved dark preference', () async {
      SharedPreferences.setMockInitialValues({
        StaffThemeController.prefsKey: true,
      });
      final ctrl = StaffThemeController(isDark: false);
      await ctrl.load();
      expect(ctrl.isDark, isTrue);
    });

    test('setDark no-ops when already loaded with same value', () async {
      final ctrl = StaffThemeController(isDark: true);
      await ctrl.load();
      await ctrl.setDark(true);
      expect(ctrl.isDark, isTrue);
    });
  });

  group('StaffThemeShell.themeFor', () {
    test('builds light and dark Material 3 themes', () {
      final dark = StaffThemeShell.themeFor(isDark: true);
      final light = StaffThemeShell.themeFor(isDark: false);
      expect(dark.colorScheme.brightness, Brightness.dark);
      expect(light.colorScheme.brightness, Brightness.light);
      expect(dark.useMaterial3, isTrue);
      expect(light.useMaterial3, isTrue);
    });
  });

  testWidgets('StaffThemeShell and toggle flip brightness', (tester) async {
    final ctrl = StaffThemeController(isDark: true);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: ctrl,
        child: MaterialApp(
          home: StaffThemeShell(
            child: Scaffold(
              appBar: AppBar(
                actions: const [StaffThemeToggleButton()],
              ),
              body: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );

    expect(ctrl.isDark, isTrue);
    expect(find.text(AppStrings.staffThemeLightLabel), findsOneWidget);

    await tester.tap(find.byType(StaffThemeToggleButton));
    await tester.pumpAndSettle();

    expect(ctrl.isDark, isFalse);
    expect(find.text(AppStrings.staffThemeDarkLabel), findsOneWidget);
  });
}
