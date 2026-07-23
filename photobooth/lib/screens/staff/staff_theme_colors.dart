import 'package:flutter/material.dart';

import '../../views/widgets/app_colors.dart';

/// Theme-aware colors for staff UI (works under [StaffThemeShell]).
abstract final class StaffThemeColors {
  static const success = Color(0xFF57D999);
  static const info = Color(0xFF5FD3E8);
  static const warning = Color(0xFFE0A94D);
  static const _darkCard = Color(0xFF141A2C);

  static Color title(BuildContext context) => AppColors.of(context).textColor;

  static Color muted(BuildContext context) =>
      AppColors.of(context).secondaryTextColor;

  static Color mutedSoft(BuildContext context) =>
      AppColors.of(context).secondaryTextColor.withValues(alpha: 0.75);

  static Color card(BuildContext context) {
    final colors = AppColors.of(context);
    if (colors.isDarkMode) {
      return _darkCard.withValues(alpha: 0.88);
    }
    return colors.cardBackgroundColor;
  }

  static Color cardBorder(BuildContext context) =>
      AppColors.of(context).borderColor.withValues(alpha: 0.4);

  static Color chipIdleBg(BuildContext context) =>
      AppColors.of(context).textColor.withValues(alpha: 0.08);

  static Color chipIdleBorder(BuildContext context) =>
      AppColors.of(context).textColor.withValues(alpha: 0.24);
}
