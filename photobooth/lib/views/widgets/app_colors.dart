import 'package:flutter/material.dart';

/// AppColors class that provides theme-aware colors based on Material theme (light/dark).
///
/// Usage:
/// ```dart
/// AppColors.of(context).backgroundColor
/// AppColors.of(context).textColor
/// ```
class AppColors {
  final BuildContext context;

  const AppColors(this.context);

  /// Factory constructor to get AppColors instance
  factory AppColors.of(BuildContext context) {
    return AppColors(context);
  }

  ThemeData get _theme => Theme.of(context);
  ColorScheme get _colorScheme => _theme.colorScheme;

  /// Get the current brightness (light or dark)
  Brightness get brightness => _theme.brightness;

  /// Check if dark mode is active
  bool get isDarkMode => brightness == Brightness.dark;

  /// Background color - adapts to theme
  Color get backgroundColor => _colorScheme.surface;

  /// Text color - adapts to theme
  Color get textColor => _colorScheme.onSurface;

  /// Secondary text color - adapts to theme
  Color get secondaryTextColor => _colorScheme.onSurfaceVariant;

  /// Surface color (for cards, containers) - adapts to theme
  Color get surfaceColor => _colorScheme.surface;

  /// Card background color - slightly elevated from background
  Color get cardBackgroundColor => _colorScheme.surfaceContainerHighest;

  /// Divider color - adapts to theme
  Color get dividerColor => _colorScheme.outlineVariant;

  /// Border color - adapts to theme
  Color get borderColor => _colorScheme.outline;

  /// Shadow color for overlays - adapts to theme
  Color get shadowColor =>
      isDarkMode
          ? Colors.black.withValues(alpha: 0.5)
          : Colors.black.withValues(alpha: 0.3);

  /// Overlay background for semi-transparent overlays - adapts to theme
  Color get overlayBackground =>
      isDarkMode
          ? Colors.black.withValues(alpha: 0.6)
          : Colors.black.withValues(alpha: 0.3);

  /// Error color - consistent across themes
  Color get errorColor => _colorScheme.error;

  /// Success color - consistent across themes
  Color get successColor => _colorScheme.tertiary;

  /// Warning color - consistent across themes
  Color get warningColor => _colorScheme.error;

  /// Primary color - consistent across themes
  Color get primaryColor => _colorScheme.primary;

  /// Button text color - for colored buttons (primary, etc.)
  Color get buttonTextColor => _colorScheme.onPrimary;
}

