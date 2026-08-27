import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/strip_models.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_view.dart';
import 'package:photobooth/utils/capture_session_kind.dart';
import 'package:photobooth/utils/classic_capture_intent.dart';
import 'package:photobooth/utils/classic_shot_mode.dart';
import 'package:photobooth/utils/classic_strip_scrub_coordinator.dart';
import 'package:photobooth/utils/fotoflashback_navigation.dart';
import 'package:photobooth/utils/route_args.dart';

import '../fixtures/theme_fixtures.dart';

void main() {
  tearDown(() {
    ClassicCaptureIntent.resetForTests();
    ClassicStripScrubCoordinator.instance.resetForTests();
    debugFotoFlashbackCapturePageBuilder = null;
  });

  test('buildClassicCaptureRouteArgs defaults to 4-shot strip', () {
    final theme = sampleTheme('strip').copyWith((p) {
      p.tier = 'photo_strip';
    });
    final args = buildClassicCaptureRouteArgs(
      theme: theme,
      shotMode: ClassicShotMode.fourShot,
    );
    expect(args.isFlashbackMultiShot, isTrue);
    expect(args.isFlashbackStrip, isTrue);
    expect(args.multiShotTotal, kStripShotCount);
    expect(args.flashbackTheme?.id, 'strip');
    expect(args.classicShotMode, ClassicShotMode.fourShot);
  });

  test('buildClassicCaptureRouteArgs supports Classic 1-shot', () {
    final theme = sampleTheme('strip1').copyWith((p) {
      p.tier = 'photo_strip';
    });
    final args = buildClassicCaptureRouteArgs(
      theme: theme,
      shotMode: ClassicShotMode.single6x4,
    );
    expect(args.isFlashbackSingle6x4, isTrue);
    expect(args.isFlashbackStrip, isFalse);
    expect(args.multiShotTotal, 1);
    expect(args.classicShotMode, ClassicShotMode.single6x4);
    expect(args.resolvedShotTotal, 1);
  });

  test('ClassicCaptureIntent is armed for Android TV before navigate', () {
    final theme = sampleTheme('strip2').copyWith((p) {
      p.tier = 'photo_strip';
    });
    ClassicCaptureIntent.beginClassic(
      mode: ClassicShotMode.single6x4,
      theme: theme,
    );
    expect(
      ClassicCaptureIntent.peekKind()?.name,
      CaptureSessionKind.classicOneShot.name,
    );
    expect(ClassicCaptureIntent.peekTheme()?.id, 'strip2');
  });

  test('FlashbackFilterArgs.resolvedShotMode drives back-to-capture mode', () {
    final theme = sampleTheme('strip-back').copyWith((p) {
      p.tier = 'photo_strip';
    });
    expect(
      FlashbackFilterArgs(
        theme: theme,
        imageDataUrls: const ['one'],
        classicShotMode: ClassicShotMode.single6x4,
      ).resolvedShotMode,
      ClassicShotMode.single6x4,
    );
    final args = buildClassicCaptureRouteArgs(
      theme: theme,
      shotMode: ClassicShotMode.single6x4,
      awaitGuestStart: true,
    );
    expect(args.multiShotTotal, 1);
    expect(args.classicShotMode, ClassicShotMode.single6x4);
    expect(args.awaitGuestStart, isTrue);
    expect(args.flashbackTheme?.id, 'strip-back');
  });

  test('Classic 1-shot route args never imply a 4-shot strip', () {
    final theme = sampleTheme('strip-one').copyWith((p) {
      p.tier = 'photo_strip';
    });
    final args = buildClassicCaptureRouteArgs(
      theme: theme,
      shotMode: ClassicShotMode.single6x4,
    );
    expect(args.resolvedShotTotal, 1);
    expect(args.isFlashbackSingle6x4, isTrue);
    expect(args.isFlashbackStrip, isFalse);
    expect(args.classicShotMode?.shotCount, 1);
  });

  testWidgets('navigateToFotoFlashbackCapture pushes pose route', (tester) async {
    final theme = sampleTheme('nav-push').copyWith((p) {
      p.tier = 'photo_strip';
    });
    CaptureSessionKind? seenKind;
    CaptureRouteArgs? seenArgs;
    debugFotoFlashbackCapturePageBuilder = ({
      required sessionKind,
      required captureArgs,
    }) {
      seenKind = sessionKind;
      seenArgs = captureArgs;
      return const Scaffold(body: Text('pose-stub'));
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () {
                navigateToFotoFlashbackCapture(
                  context: context,
                  theme: theme,
                  shotMode: ClassicShotMode.fourShot,
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
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('pose-stub'), findsOneWidget);
    expect(seenKind, CaptureSessionKind.classicFourShot);
    expect(seenArgs?.multiShotTotal, kStripShotCount);
    expect(ClassicCaptureIntent.peekTheme()?.id, 'nav-push');

    Navigator.of(tester.element(find.text('pose-stub'))).pop();
    await tester.pumpAndSettle();
  });

  testWidgets('navigateToFotoFlashbackCapture replace + awaitGuestStart',
      (tester) async {
    final theme = sampleTheme('nav-replace').copyWith((p) {
      p.tier = 'photo_strip';
    });
    CaptureRouteArgs? seenArgs;
    debugFotoFlashbackCapturePageBuilder = ({
      required sessionKind,
      required captureArgs,
    }) {
      seenArgs = captureArgs;
      return Scaffold(body: Text('pose-${sessionKind.name}'));
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () {
                navigateToFotoFlashbackCapture(
                  context: context,
                  theme: theme,
                  shotMode: ClassicShotMode.single6x4,
                  replace: true,
                  awaitGuestStart: true,
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
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('pose-classicOneShot'), findsOneWidget);
    expect(seenArgs?.multiShotTotal, 1);
    expect(seenArgs?.awaitGuestStart, isTrue);
    expect(ClassicCaptureIntent.peekKind(), CaptureSessionKind.classicOneShot);
  });

  testWidgets('navigateBackToClassicCaptureFromLooks resets scrub and replaces',
      (tester) async {
    final theme = sampleTheme('nav-back').copyWith((p) {
      p.tier = 'photo_strip';
    });
    ClassicStripScrubCoordinator.instance.enqueueShot(
      encodeShotDataUrl: () async => 'data:image/jpeg;base64,x',
      enableScrub: false,
    );
    expect(ClassicStripScrubCoordinator.instance.shotCount, 1);

    debugFotoFlashbackCapturePageBuilder = ({
      required sessionKind,
      required captureArgs,
    }) {
      return const Scaffold(body: Text('looks-back-pose'));
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () {
                navigateBackToClassicCaptureFromLooks(
                  context: context,
                  theme: theme,
                  shotMode: ClassicShotMode.fourShot,
                );
              },
              child: const Text('back'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('looks-back-pose'), findsOneWidget);
    expect(ClassicStripScrubCoordinator.instance.shotCount, 0);
    expect(ClassicCaptureIntent.peekTheme()?.id, 'nav-back');
  });

  testWidgets('navigate helpers no-op when context is unmounted', (tester) async {
    final theme = sampleTheme('nav-unmounted').copyWith((p) {
      p.tier = 'photo_strip';
    });
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(captured.mounted, isFalse);

    await navigateToFotoFlashbackCapture(
      context: captured,
      theme: theme,
      shotMode: ClassicShotMode.fourShot,
    );
    await navigateBackToClassicCaptureFromLooks(
      context: captured,
      theme: theme,
      shotMode: ClassicShotMode.single6x4,
    );
    expect(ClassicCaptureIntent.peekTheme(), isNull);
  });

  test('buildFotoFlashbackCapturePage defaults to PhotoCaptureScreen', () {
    debugFotoFlashbackCapturePageBuilder = null;
    final theme = sampleTheme('nav-page').copyWith((p) {
      p.tier = 'photo_strip';
    });
    final args = buildClassicCaptureRouteArgs(
      theme: theme,
      shotMode: ClassicShotMode.single6x4,
      awaitGuestStart: true,
    );
    final page = buildFotoFlashbackCapturePage(
      sessionKind: CaptureSessionKind.classicOneShot,
      captureArgs: args,
      awaitGuestStart: true,
    );
    expect(page, isA<PhotoCaptureScreen>());
    expect(page.key, isA<ValueKey<String>>());
    expect('${page.key}', contains('pose-classicOneShot-1-await'));
  });
}
