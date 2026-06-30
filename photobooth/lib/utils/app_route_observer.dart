import 'package:flutter/widgets.dart';

/// Shared [RouteObserver] for pausing offscreen animations and timers.
final RouteObserver<PageRoute<void>> appRouteObserver =
    RouteObserver<PageRoute<void>>();
