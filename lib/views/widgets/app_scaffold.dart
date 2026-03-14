import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Common scaffold widget that handles app bar, back button, and status bar padding.
///
/// This widget provides a consistent way to create screens with:
/// - Optional app bar with title or custom middle widget
/// - Optional back button with custom navigation
/// - Optional extension behind status bar with proper padding
/// - SafeArea option for screens that don't extend behind status bar
/// - Automatic device-aware padding calculation
class AppScaffold extends StatelessWidget {
  /// Title for the app bar (mutually exclusive with [middle])
  final String? title;

  /// Custom widget for the app bar middle (mutually exclusive with [title])
  final Widget? middle;

  /// Actions to display in the app bar
  final List<Widget>? actions;

  /// Whether to show a back button
  final bool showBackButton;

  /// Custom back button action (if null, uses Navigator.pop())
  final VoidCallback? onBackPressed;

  /// Whether the screen should extend behind the status bar
  final bool extendBehindStatusBar;

  /// Background color of the scaffold
  final Color? backgroundColor;

  /// The main content of the screen
  final Widget child;

  /// Whether to automatically imply leading (back button)
  final bool automaticallyImplyLeading;

  /// Whether to apply automatic device-aware horizontal padding
  final bool applyHorizontalPadding;

  /// Whether to apply automatic device-aware vertical padding
  final bool applyVerticalPadding;

  /// Custom horizontal padding
  final double? horizontalPadding;

  /// Custom vertical padding
  final double? verticalPadding;

  const AppScaffold({
    super.key,
    this.title,
    this.middle,
    this.actions,
    this.showBackButton = false,
    this.onBackPressed,
    this.extendBehindStatusBar = false,
    this.backgroundColor,
    required this.child,
    this.automaticallyImplyLeading = true,
    this.applyHorizontalPadding = false,
    this.applyVerticalPadding = false,
    this.horizontalPadding,
    this.verticalPadding,
  }) : assert(
          title == null || middle == null,
          'Cannot provide both title and middle widget',
        );

  @override
  Widget build(BuildContext context) {
    final appBar = _buildAppBar(context);
    final content = extendBehindStatusBar
        ? _buildContentWithPadding(context)
        : SafeArea(child: child);

    return Scaffold(
      backgroundColor: backgroundColor ?? Theme.of(context).colorScheme.surface,
      appBar: appBar,
      body: content,
    );
  }

  PreferredSizeWidget? _buildAppBar(BuildContext context) {
    if (title == null && middle == null && actions == null && !showBackButton) {
      return null;
    }

    Widget? leading;
    if (showBackButton) {
      leading = AppActionButton(
        icon: CupertinoIcons.back,
        onPressed: onBackPressed ?? () => Navigator.of(context).pop(),
      );
    }

    return AppTopBar(
      title: title,
      middle: middle,
      actions: actions,
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
    );
  }

  Widget _buildContentWithPadding(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;
    const navBarHeight = kToolbarHeight;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    final screenWidth = MediaQuery.of(context).size.width;
    final scaleFactor = (screenWidth / 400.0).clamp(0.8, 2.0);

    final double horizontal = horizontalPadding ??
        (applyHorizontalPadding ? 8.0 + (scaleFactor * 8.0) : 0.0);
    final double vertical =
        verticalPadding ?? (applyVerticalPadding ? 2.0 + (scaleFactor * 3.0) : 0.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: double.infinity,
          height: constraints.maxHeight,
          padding: EdgeInsets.only(
            top: statusBarHeight + navBarHeight + vertical,
            bottom: bottomPadding + vertical,
            left: horizontal,
            right: horizontal,
          ),
          child: child,
        );
      },
    );
  }
}
