import 'package:flutter/material.dart';
import '../../utils/constants.dart';
import 'app_colors.dart';
import 'leading_with_alice.dart';

/// Common theme configuration for the app (Material).
class AppTheme {
  // Fallback colors when Theme is not available
  static const Color primaryColor = Colors.blue;
  static const Color backgroundColor = Colors.white;
  static const Color textColor = Colors.black;
  static const Color secondaryTextColor = Colors.grey;

  // Button styles
  static const double buttonHeight = AppConstants.kButtonHeight;
  static const double buttonBorderRadius = 12.0;

  // Text styles
  static TextStyle get titleTextStyle => const TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: textColor,
  );

  // Theme-aware title style
  static TextStyle titleTextStyleForContext(BuildContext context) {
    final appColors = AppColors.of(context);
    return TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      color: appColors.textColor,
    );
  }

  static TextStyle get bodyTextStyle => const TextStyle(
    fontSize: 15,
    color: textColor,
  );

  static TextStyle get buttonTextStyle => const TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );
}

/// Material AppBar used as the top bar across the app.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? middle;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;

  const AppTopBar({
    super.key,
    this.title,
    this.middle,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);

    return AppBar(
      title: middle ?? (title != null ? Text(
        title!,
        style: AppTheme.titleTextStyleForContext(context),
      ) : null),
      leading: leading,
      actions: [
        ...?actions?.map((action) => ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 48),
              child: action,
            )),
        const AppBarAliceAction(),
      ],
      automaticallyImplyLeading: automaticallyImplyLeading,
      backgroundColor: appColors.backgroundColor,
      foregroundColor: appColors.textColor,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Divider(height: 0.5, color: appColors.dividerColor),
      ),
    );
  }
}

/// Common bottom continue button (Material ElevatedButton).
class AppContinueButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? height;
  final EdgeInsets? padding;

  const AppContinueButton({
    super.key,
    this.text = 'Continue',
    this.onPressed,
    this.isLoading = false,
    this.backgroundColor,
    this.foregroundColor,
    this.height,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > AppConstants.kTabletBreakpoint;

    return SafeArea(
      child: Padding(
        padding: padding ?? EdgeInsets.all(isTablet ? 20.0 : 16.0),
        child: SizedBox(
          width: double.infinity,
          height: height ?? AppTheme.buttonHeight,
          child: ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: backgroundColor ?? appColors.primaryColor,
              foregroundColor: foregroundColor ?? appColors.buttonTextColor,
              disabledBackgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.buttonBorderRadius),
              ),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(text, style: AppTheme.buttonTextStyle),
          ),
        ),
      ),
    );
  }
}

/// Common action button (Material IconButton).
class AppActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;
  final double? iconSize;

  const AppActionButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.color,
    this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);

    return IconButton(
      icon: Icon(icon, size: iconSize ?? 28.0),
      color: color ?? appColors.primaryColor,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/// Common full-width button with icon (Material ElevatedButton).
class AppButtonWithIcon extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? height;

  const AppButtonWithIcon({
    super.key,
    required this.text,
    required this.icon,
    this.onPressed,
    this.isLoading = false,
    this.backgroundColor,
    this.foregroundColor,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);

    return SizedBox(
      width: double.infinity,
      height: height ?? AppTheme.buttonHeight,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor ?? appColors.primaryColor,
          foregroundColor: foregroundColor ?? appColors.buttonTextColor,
          disabledBackgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.buttonBorderRadius),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: 8),
                  Text(text, style: AppTheme.buttonTextStyle),
                ],
              ),
      ),
    );
  }
}

/// Common outlined button (Material OutlinedButton).
class AppOutlinedButton extends StatelessWidget {
  final String text;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color? borderColor;
  final Color? textColor;
  final double? height;

  const AppOutlinedButton({
    super.key,
    required this.text,
    this.icon,
    this.onPressed,
    this.borderColor,
    this.textColor,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);

    return SizedBox(
      width: double.infinity,
      height: height ?? AppTheme.buttonHeight,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: textColor ?? appColors.primaryColor,
          side: BorderSide(
            color: borderColor ?? appColors.primaryColor,
            width: 1.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.buttonBorderRadius),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: textColor ?? appColors.primaryColor),
              const SizedBox(width: 8),
            ],
            Text(text, style: AppTheme.buttonTextStyle.copyWith(color: textColor ?? appColors.primaryColor)),
          ],
        ),
      ),
    );
  }
}
