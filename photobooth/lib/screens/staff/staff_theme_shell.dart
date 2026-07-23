import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/app_strings.dart';
import 'staff_theme_controller.dart';

/// Applies staff light/dark [ThemeData] without changing the guest kiosk theme.
class StaffThemeShell extends StatelessWidget {
  const StaffThemeShell({super.key, required this.child});

  final Widget child;

  static ThemeData themeFor({required bool isDark}) {
    final brightness = isDark ? Brightness.dark : Brightness.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF3B82F6),
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardColor: isDark
          ? const Color(0xFF141A2C).withValues(alpha: 0.88)
          : scheme.surfaceContainerHighest,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<StaffThemeController>().isDark;
    return Theme(
      data: themeFor(isDark: isDark),
      child: child,
    );
  }
}

/// Compact AppBar control — icon + Light/Dark label so it stays visible on web.
class StaffThemeToggleButton extends StatelessWidget {
  const StaffThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<StaffThemeController>();
    final scheme = Theme.of(context).colorScheme;
    final goingLight = ctrl.isDark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurface,
          backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () => ctrl.toggle(),
        icon: Icon(
          goingLight ? Icons.wb_sunny_outlined : Icons.nightlight_round,
          size: 18,
        ),
        label: Text(
          goingLight
              ? AppStrings.staffThemeLightLabel
              : AppStrings.staffThemeDarkLabel,
        ),
      ),
    );
  }
}
