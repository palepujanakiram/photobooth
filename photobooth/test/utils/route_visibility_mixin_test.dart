import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/app_route_observer.dart';
import 'package:photobooth/utils/route_visibility_mixin.dart';

class _VisibilityHost extends StatefulWidget {
  const _VisibilityHost({required this.onVisible});

  final ValueChanged<bool> onVisible;

  @override
  State<_VisibilityHost> createState() => _VisibilityHostState();
}

class _VisibilityHostState extends State<_VisibilityHost>
    with RouteVisibilityMixin<_VisibilityHost> {
  @override
  void onRouteVisibilityChanged(bool visible) {
    widget.onVisible(visible);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ElevatedButton(
        key: const Key('push-overlay'),
        onPressed: () {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (overlayContext) => Scaffold(
                body: ElevatedButton(
                  key: const Key('pop-overlay'),
                  onPressed: () => Navigator.of(overlayContext).pop(),
                  child: const Text('pop'),
                ),
              ),
            ),
          );
        },
        child: const Text('push'),
      ),
    );
  }
}

class _BareHost extends StatefulWidget {
  const _BareHost();

  @override
  State<_BareHost> createState() => _BareHostState();
}

class _BareHostState extends State<_BareHost> with RouteVisibilityMixin<_BareHost> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ElevatedButton(
        key: const Key('bare-push'),
        onPressed: () {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('cover')),
            ),
          );
        },
        child: const Text('cover'),
      ),
    );
  }
}

void main() {
  testWidgets('RouteVisibilityMixin reports cover and uncover', (tester) async {
    final visible = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [appRouteObserver],
        home: _VisibilityHost(onVisible: visible.add),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('push-overlay')));
    await tester.pumpAndSettle();
    expect(visible, contains(false));

    await tester.tap(find.byKey(const Key('pop-overlay')));
    await tester.pumpAndSettle();
    expect(visible.last, isTrue);
  });

  testWidgets('RouteVisibilityMixin default hooks are safe', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        navigatorObservers: [appRouteObserver],
        home: Builder(
          builder: (context) => ElevatedButton(
            key: const Key('open-bare'),
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => const _BareHost()),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-bare')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bare-push')));
    await tester.pumpAndSettle();

    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    navKey.currentState!.pop();
    await tester.pumpAndSettle();
  });
}
