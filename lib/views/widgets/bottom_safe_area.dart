import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/widgets.dart';

/// Minimum bottom padding when the system reports no inset (e.g. Android TV 11).
const double kBottomSafeAreaMinInset = 48.0;

/// On Android (e.g. Android TV 11), the system may report 0 for bottom view inset.
/// Returns extra bottom padding so content stays above the system nav bar.
/// On other platforms returns 0.
double effectiveBottomInset(BuildContext context) {
  if (defaultTargetPlatform != TargetPlatform.android) return 0;
  final padding = MediaQuery.paddingOf(context).bottom;
  return padding >= kBottomSafeAreaMinInset ? 0 : (kBottomSafeAreaMinInset - padding);
}

/// Wraps [child] with bottom padding when on Android and the system reports
/// less than [kBottomSafeAreaMinInset]. Use around screen content so it does
/// not overlap the Android TV / system bottom bar.
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
