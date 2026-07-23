import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/staff/staff_theme_colors.dart';
import 'package:photobooth/screens/staff/staff_theme_shell.dart';

void main() {
  Future<BuildContext> pumpTheme(
    WidgetTester tester, {
    required bool isDark,
  }) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: StaffThemeShell.themeFor(isDark: isDark),
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return captured;
  }

  testWidgets('StaffThemeColors adapts title/muted/card for dark', (tester) async {
    final context = await pumpTheme(tester, isDark: true);
    expect(StaffThemeColors.title(context), isNot(equals(Colors.black)));
    expect(StaffThemeColors.muted(context), isNotNull);
    expect(StaffThemeColors.mutedSoft(context), isNotNull);
    expect(StaffThemeColors.card(context).a, lessThan(1.0));
    expect(StaffThemeColors.cardBorder(context), isNotNull);
    expect(StaffThemeColors.chipIdleBg(context), isNotNull);
    expect(StaffThemeColors.chipIdleBorder(context), isNotNull);
    expect(StaffThemeColors.success, const Color(0xFF57D999));
    expect(StaffThemeColors.info, const Color(0xFF5FD3E8));
    expect(StaffThemeColors.warning, const Color(0xFFE0A94D));
  });

  testWidgets('StaffThemeColors uses elevated surface card in light', (tester) async {
    final context = await pumpTheme(tester, isDark: false);
    final card = StaffThemeColors.card(context);
    expect(card.a, equals(1.0));
    expect(StaffThemeColors.title(context), isNotNull);
  });
}
