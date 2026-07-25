import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/strip_models.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/utils/fotoflashback_navigation.dart';
import 'package:photobooth/utils/route_args.dart';

import '../fixtures/theme_fixtures.dart';

void main() {
  testWidgets('navigateToFotoFlashbackCapture opens multi-shot POSE', (
    tester,
  ) async {
    final theme = sampleTheme('strip').copyWith((p) {
      p.tier = 'photo_strip';
    });
    Object? pushedArgs;
    String? pushedName;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                navigateToFotoFlashbackCapture(
                  context: context,
                  theme: theme,
                );
              },
              child: const Text('go'),
            );
          },
        ),
        onGenerateRoute: (settings) {
          pushedName = settings.name;
          pushedArgs = settings.arguments;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const Scaffold(body: Text('capture')),
          );
        },
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(pushedName, AppConstants.kRouteCapture);
    expect(pushedArgs, isA<CaptureRouteArgs>());
    final args = pushedArgs! as CaptureRouteArgs;
    expect(args.isFlashbackMultiShot, isTrue);
    expect(args.multiShotTotal, kStripShotCount);
    expect(args.flashbackTheme?.id, 'strip');
  });

  testWidgets('navigateToFotoFlashbackCapture replace uses pushReplacement', (
    tester,
  ) async {
    final theme = sampleTheme('strip2').copyWith((p) => p.tier = 'photo_strip');
    String? pushedName;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                navigateToFotoFlashbackCapture(
                  context: context,
                  theme: theme,
                  replace: true,
                );
              },
              child: const Text('replace'),
            );
          },
        ),
        onGenerateRoute: (settings) {
          pushedName = settings.name;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const Scaffold(body: Text('capture-replace')),
          );
        },
      ),
    );

    await tester.tap(find.text('replace'));
    await tester.pumpAndSettle();
    expect(pushedName, AppConstants.kRouteCapture);
    expect(find.text('capture-replace'), findsOneWidget);
    expect(find.text('replace'), findsNothing);
  });
}
