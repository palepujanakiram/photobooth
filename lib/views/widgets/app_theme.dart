import 'package:flutter/cupertino.dart';
import '../../utils/constants.dart';
import 'app_colors.dart';

/// Common theme configuration for the app
class AppTheme {
  // Colors
  static const Color primaryColor = CupertinoColors.systemBlue;
  static const Color backgroundColor = CupertinoColors.white;
  static const Color textColor = CupertinoColors.black;
  static const Color secondaryTextColor = CupertinoColors.systemGrey;
  
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
    color: CupertinoColors.white,
  );
}

/// Common Cupertino-style top bar widget
class AppTopBar extends StatelessWidget implements ObstructingPreferredSizeWidget {
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
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    
    return CupertinoNavigationBar(
      middle: middle ?? (title != null ? Text(
        title!,
        style: AppTheme.titleTextStyleForContext(context),
      ) : null),
      leading: leading,
      trailing: actions != null && actions!.isNotEmpty
          ? Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: actions!.map((action) => 
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 48),
                  child: action,
                )
              ).toList(),
            )
          : null,
      automaticallyImplyLeading: automaticallyImplyLeading,
      backgroundColor: appColors.backgroundColor,
      border: Border(
        bottom: BorderSide(
          color: appColors.dividerColor,
          width: 0.5,
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(44.0);

  @override
  bool shouldFullyObstruct(BuildContext context) => true;
}

/// Common Cupertino-style bottom continue button
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > AppConstants.kTabletBreakpoint;
    
    return SafeArea(
      child: Padding(
        padding: padding ?? EdgeInsets.all(isTablet ? 20.0 : 16.0),
        child: SizedBox(
          width: double.infinity,
          height: height ?? AppTheme.buttonHeight,
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            color: backgroundColor ?? AppTheme.primaryColor,
            disabledColor: CupertinoColors.systemGrey3,
            onPressed: isLoading ? null : onPressed,
            borderRadius: BorderRadius.circular(AppTheme.buttonBorderRadius),
            child: isLoading
                ? const CupertinoActivityIndicator(
                    color: CupertinoColors.white,
                  )
                : Text(
                    text,
                    style: AppTheme.buttonTextStyle.copyWith(
                      color: foregroundColor ?? CupertinoColors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Common Cupertino-style action button (for icon buttons)
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
    return SizedBox(
      width: 44.0,
      height: 44.0,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: Icon(
          icon,
          color: color ?? AppTheme.primaryColor,
          size: iconSize ?? 28.0,
        ),
      ),
    );
  }
}

/// Common Cupertino-style full-width button with icon
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
    return SizedBox(
      width: double.infinity,
      height: height ?? AppTheme.buttonHeight,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        color: backgroundColor ?? AppTheme.primaryColor,
        disabledColor: CupertinoColors.systemGrey3,
        onPressed: isLoading ? null : onPressed,
        borderRadius: BorderRadius.circular(AppTheme.buttonBorderRadius),
        child: isLoading
            ? const CupertinoActivityIndicator(
                color: CupertinoColors.white,
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isLoading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CupertinoActivityIndicator(
                        color: CupertinoColors.white,
                        radius: 10,
                      ),
                    )
                  else
                    Icon(
                      icon,
                      color: foregroundColor ?? CupertinoColors.white,
                      size: 20,
                    ),
                  const SizedBox(width: 8),
                  Text(
                    text,
                    style: AppTheme.buttonTextStyle.copyWith(
                      color: foregroundColor ?? CupertinoColors.white,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Common Cupertino-style outlined button
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
    return SizedBox(
      width: double.infinity,
      height: height ?? AppTheme.buttonHeight,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        borderRadius: BorderRadius.circular(AppTheme.buttonBorderRadius),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: borderColor ?? AppTheme.primaryColor,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(AppTheme.buttonBorderRadius),
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    color: textColor ?? AppTheme.primaryColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  text,
                  style: AppTheme.buttonTextStyle.copyWith(
                    color: textColor ?? AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

