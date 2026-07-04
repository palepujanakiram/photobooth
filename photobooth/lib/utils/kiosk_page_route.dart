import 'package:flutter/material.dart';

/// Short cross-fade for kiosk hand-offs (Terms → POSE) so navigation feels instant.
class KioskFadePageRoute<T> extends PageRouteBuilder<T> {
  KioskFadePageRoute({
    required Widget page,
    RouteSettings? settings,
    Duration duration = const Duration(milliseconds: 120),
  }) : super(
          settings: settings,
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: duration,
          reverseTransitionDuration: duration,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(opacity: curved, child: child);
          },
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
