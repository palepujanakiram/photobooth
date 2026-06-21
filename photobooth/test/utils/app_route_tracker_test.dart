import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/app_route_tracker.dart';
import 'package:photobooth/utils/constants.dart';

void main() {
  testWidgets('AppRouteTracker records pushed route name', (tester) async {
    final tracker = AppRouteTracker();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [tracker],
        initialRoute: AppConstants.kRouteSplash,
        routes: {
          AppConstants.kRouteSplash: (_) => const Scaffold(body: Text('splash')),
          AppConstants.kRouteTerms: (_) => const Scaffold(body: Text('terms')),
        },
      ),
    );

    expect(tracker.currentRouteName, AppConstants.kRouteSplash);

    final context = tester.element(find.text('splash'));
    Navigator.of(context).pushNamed(AppConstants.kRouteTerms);
    await tester.pumpAndSettle();

    expect(tracker.currentRouteName, AppConstants.kRouteTerms);
  });

  testWidgets('AppRouteTracker records popped route name', (tester) async {
    final tracker = AppRouteTracker();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [tracker],
        initialRoute: AppConstants.kRouteSplash,
        routes: {
          AppConstants.kRouteSplash: (_) => const Scaffold(body: Text('splash')),
          AppConstants.kRouteTerms: (_) => const Scaffold(body: Text('terms')),
        },
      ),
    );

    final context = tester.element(find.text('splash'));
    Navigator.of(context).pushNamed(AppConstants.kRouteTerms);
    await tester.pumpAndSettle();
    expect(tracker.currentRouteName, AppConstants.kRouteTerms);

    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(tracker.currentRouteName, AppConstants.kRouteSplash);
  });

  testWidgets('AppRouteTracker records replaced route name', (tester) async {
    final tracker = AppRouteTracker();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [tracker],
        initialRoute: AppConstants.kRouteSplash,
        routes: {
          AppConstants.kRouteSplash: (_) => const Scaffold(body: Text('splash')),
          AppConstants.kRouteTerms: (_) => const Scaffold(body: Text('terms')),
        },
      ),
    );

    final context = tester.element(find.text('splash'));
    Navigator.of(context).pushReplacementNamed(AppConstants.kRouteTerms);
    await tester.pumpAndSettle();
    expect(tracker.currentRouteName, AppConstants.kRouteTerms);
  });

  test('AppRouteTracker didRemove sets previous route', () {
    final tracker = AppRouteTracker();
    final routeA = MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/a'),
      builder: (_) => const SizedBox.shrink(),
    );
    final routeB = MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/b'),
      builder: (_) => const SizedBox.shrink(),
    );

    tracker.didPush(routeA, null);
    expect(tracker.currentRouteName, '/a');

    tracker.didRemove(routeB, routeA);
    expect(tracker.currentRouteName, '/a');
  });
}
