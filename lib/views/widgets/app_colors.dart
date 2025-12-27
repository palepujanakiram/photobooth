import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// AppColors class that provides theme-aware colors based on system dark/light mode
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
  
  /// Get the current brightness (light or dark)
  Brightness get brightness {
    return CupertinoTheme.brightnessOf(context);
  }
  
  /// Check if dark mode is active
  bool get isDarkMode {
    return brightness == Brightness.dark;
  }
  
  /// Background color - adapts to theme
  Color get backgroundColor {
    return isDarkMode 
        ? CupertinoColors.black 
        : CupertinoColors.white;
  }
  
  /// Text color - adapts to theme
  Color get textColor {
    return isDarkMode 
        ? CupertinoColors.white 
        : CupertinoColors.black;
  }
  
  /// Secondary text color - adapts to theme
  Color get secondaryTextColor {
    return isDarkMode 
        ? CupertinoColors.systemGrey 
        : CupertinoColors.systemGrey;
  }
  
  /// Surface color (for cards, containers) - adapts to theme
  Color get surfaceColor {
    return isDarkMode 
        ? CupertinoColors.systemGrey6.darkColor 
        : CupertinoColors.white;
  }
  
  /// Border color - adapts to theme
  Color get borderColor {
    return isDarkMode 
        ? CupertinoColors.separator.darkColor 
        : CupertinoColors.separator;
  }
  
  /// Shadow color for overlays - adapts to theme
  Color get shadowColor {
    return isDarkMode 
        ? Colors.black.withValues(alpha: 0.5) 
        : Colors.black.withValues(alpha: 0.3);
  }
  
  /// Overlay background for semi-transparent overlays - adapts to theme
  Color get overlayBackground {
    return isDarkMode 
        ? Colors.black.withValues(alpha: 0.6) 
        : Colors.black.withValues(alpha: 0.3);
  }
  
  /// Error color - consistent across themes
  Color get errorColor {
    return CupertinoColors.systemRed;
  }
  
  /// Success color - consistent across themes
  Color get successColor {
    return CupertinoColors.systemGreen;
  }
  
  /// Warning color - consistent across themes
  Color get warningColor {
    return CupertinoColors.systemOrange;
  }
  
  /// Primary color - consistent across themes
  Color get primaryColor {
    return CupertinoColors.systemBlue;
  }
  
  /// Button text color - always white for colored buttons (blue, etc.)
  /// This ensures good contrast on colored button backgrounds
  Color get buttonTextColor {
    return CupertinoColors.white;
  }
}

