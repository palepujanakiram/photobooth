import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/app_route_observer.dart';

void main() {
  test('appRouteObserver is a shared RouteObserver', () {
    expect(appRouteObserver, isNotNull);
  });
}
