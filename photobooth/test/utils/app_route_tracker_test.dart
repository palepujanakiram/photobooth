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

  testWidgets(
      'AppRouteTracker does not notify ListenableBuilder during Navigator mount',
      (tester) async {
    final tracker = AppRouteTracker();
    FlutterError? caught;
    final oldOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exception is FlutterError) {
        caught = details.exception as FlutterError;
      }
      oldOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = oldOnError);

    await tester.pumpWidget(
      ListenableBuilder(
        listenable: tracker,
        builder: (context, _) {
          return MaterialApp(
            navigatorObservers: [tracker],
            home: Text(tracker.currentRouteName ?? 'none'),
          );
        },
      ),
    );

    expect(caught, isNull);
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
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
