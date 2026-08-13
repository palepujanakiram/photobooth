import 'package:flutter/widgets.dart';

/// Tracks the top [Navigator] route name for global UI (e.g. debug HUD gating).
class AppRouteTracker extends NavigatorObserver with ChangeNotifier {
  String? _currentRouteName;
  bool _notifyScheduled = false;

  String? get currentRouteName => _currentRouteName;

  void _set(Route<dynamic>? route) {
    final next = route?.settings.name;
    if (next == _currentRouteName) return;
    _currentRouteName = next;
    _scheduleNotify();
  }

  /// Always notify on the next frame. The first route is pushed from a Timer
  /// while [WidgetsBinding.scheduleAttachRootWidget] is still building, when
  /// [SchedulerPhase] is [SchedulerPhase.idle] — so a phase check is not enough.
  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      _notifyScheduled = false;
      notifyListeners();
    });
    binding.ensureVisualUpdate();
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
