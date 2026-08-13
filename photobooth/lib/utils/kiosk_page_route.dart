import 'package:flutter/material.dart';

/// Fade used by [KioskFadePageRoute] (extracted so unit tests can invoke it).
Widget kioskFadeTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final curved = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
  );
  return FadeTransition(opacity: curved, child: child);
}

/// Short cross-fade for kiosk hand-offs (Terms → POSE) so navigation feels instant.
class KioskFadePageRoute<T> extends PageRouteBuilder<T> {
  KioskFadePageRoute({
    required Widget page,
    super.settings,
    Duration duration = const Duration(milliseconds: 120),
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: duration,
          reverseTransitionDuration: duration,
          transitionsBuilder: kioskFadeTransition,
        );
}

/// [Navigator.pushReplacement] with [KioskFadePageRoute].
Future<T?> pushReplacementKioskFade<T extends Object?, TO extends Object?>(
  BuildContext context,
  Widget page, {
  RouteSettings? settings,
}) {
  return Navigator.of(context).pushReplacement<T, TO>(
    KioskFadePageRoute<T>(page: page, settings: settings),
  );
}
