import 'package:flutter/widgets.dart';

/// Tracks the top [Navigator] route name for global UI (e.g. debug HUD gating).
class AppRouteTracker extends NavigatorObserver with ChangeNotifier {
  String? _currentRouteName;

  String? get currentRouteName => _currentRouteName;

  void _set(Route<dynamic>? route) {
    final next = route?.settings.name;
    if (next == _currentRouteName) return;
    _currentRouteName = next;
    notifyListeners();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _set(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _set(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _set(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _set(previousRoute);
  }
}
