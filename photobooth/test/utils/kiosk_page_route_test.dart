import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/kiosk_page_route.dart';

void main() {
  test('KioskFadePageRoute uses a short fade transition', () {
    final route = KioskFadePageRoute<void>(
      page: const SizedBox.shrink(),
    );
    expect(route.transitionDuration, const Duration(milliseconds: 120));
    expect(route.reverseTransitionDuration, const Duration(milliseconds: 120));
  });

  testWidgets('pushReplacementKioskFade replaces with fade route', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () {
                pushReplacementKioskFade<void, void>(
                  context,
                  const Scaffold(body: Text('next')),
                );
              },
              child: const Text('go'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('next'), findsOneWidget);
  });

  testWidgets('kioskFadeTransition wraps child in FadeTransition', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return kioskFadeTransition(
              context,
              const AlwaysStoppedAnimation<double>(1),
              const AlwaysStoppedAnimation<double>(0),
              const Text('faded'),
            );
          },
        ),
      ),
    );
    expect(find.text('faded'), findsOneWidget);
    expect(find.byType(FadeTransition), findsWidgets);
  });

  testWidgets('KioskFadePageRoute transitionsBuilder fades child', (tester) async {
    final route = KioskFadePageRoute<void>(
      page: const Text('fade-child'),
      duration: const Duration(milliseconds: 200),
    );

    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: (_) => route,
        initialRoute: '/',
      ),
    );
    await tester.pump();
    expect(find.text('fade-child'), findsOneWidget);
  });
}
