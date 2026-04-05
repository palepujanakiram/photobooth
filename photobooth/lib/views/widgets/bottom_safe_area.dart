import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/widgets.dart';

/// Minimum bottom padding when the system reports no inset (e.g. Android TV 11).
const double kBottomSafeAreaMinInset = 48.0;

/// Height of the custom bottom bar content (debug actions). Used so screens can
/// reserve space when the bar is visible.
const double kAppBottomBarContentHeight = 48.0;

/// On Android (e.g. Android TV 11), the system may report 0 for bottom view inset.
/// Returns extra bottom padding so content stays above the system nav bar.
/// On other platforms returns 0.
double effectiveBottomInset(BuildContext context) {
  if (defaultTargetPlatform != TargetPlatform.android) return 0;
  final padding = MediaQuery.paddingOf(context).bottom;
  return padding >= kBottomSafeAreaMinInset ? 0 : (kBottomSafeAreaMinInset - padding);
}

/// Total bottom inset to reserve (system nav + optional bar). On Android uses
/// at least [kBottomSafeAreaMinInset] when system reports less.
double safeBottomInset(BuildContext context) {
  final padding = MediaQuery.paddingOf(context).bottom;
  if (defaultTargetPlatform == TargetPlatform.android) {
    return padding >= kBottomSafeAreaMinInset ? padding : kBottomSafeAreaMinInset;
  }
  return padding;
}

/// Total height of the app bottom bar (content + safe area). Use when reserving
/// space so content does not sit under the bar.
double appBottomBarTotalHeight(BuildContext context) {
  return kAppBottomBarContentHeight + safeBottomInset(context);
}

/// Wraps [child] with bottom padding so content stays above the system nav bar
/// and, when the debug bottom bar is visible (Alice provided), above the bar.
class BottomSafePadding extends StatelessWidget {
  const BottomSafePadding({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bottom = effectiveBottomInset(context);
    if (bottom <= 0) return child;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: child,
    );
  }
}
