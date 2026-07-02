import 'package:flutter/widgets.dart';

import 'app_route_observer.dart';

/// Tracks whether this [State]'s [ModalRoute] is the visible top route.
mixin RouteVisibilityMixin<T extends StatefulWidget> on State<T>
    implements RouteAware {
  bool routeIsVisible = true;
  bool _routeObserverSubscribed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeObserverSubscribed) return;
    final route = ModalRoute.of(context);
    if (route is PageRoute<void>) {
      appRouteObserver.subscribe(this, route);
      _routeObserverSubscribed = true;
    }
  }

  @override
  void dispose() {
    if (_routeObserverSubscribed) {
      appRouteObserver.unsubscribe(this);
    }
    super.dispose();
  }

  @override
  void didPush() => _updateRouteVisible(true);

  @override
  void didPopNext() => _updateRouteVisible(true);

  @override
  void didPushNext() => _updateRouteVisible(false);

  @override
  void didPop() {}

  void _updateRouteVisible(bool visible) {
    if (routeIsVisible == visible) return;
    routeIsVisible = visible;
    onRouteVisibilityChanged(visible);
  }

  /// Called when this screen becomes covered or uncovered by another route.
  void onRouteVisibilityChanged(bool visible) {}
}
