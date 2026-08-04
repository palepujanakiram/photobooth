import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/strip_models.dart';
import 'package:photobooth/utils/capture_session_kind.dart';
import 'package:photobooth/utils/classic_capture_intent.dart';
import 'package:photobooth/utils/classic_shot_mode.dart';
import 'package:photobooth/utils/fotoflashback_navigation.dart';
import 'package:photobooth/utils/route_args.dart';

import '../fixtures/theme_fixtures.dart';

void main() {
  tearDown(ClassicCaptureIntent.resetForTests);

  test('buildClassicCaptureRouteArgs defaults to 4-shot strip', () {
    final theme = sampleTheme('strip').copyWith((p) {
      p.tier = 'photo_strip';
    });
    final args = buildClassicCaptureRouteArgs(
      theme: theme,
      shotMode: ClassicShotMode.fourShot,
    );
    expect(args.isFlashbackMultiShot, isTrue);
    expect(args.isFlashbackFourShot, isTrue);
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
    expect(args.isFlashbackFourShot, isFalse);
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
    expect(args.isFlashbackFourShot, isFalse);
    expect(args.classicShotMode?.shotCount, 1);
  });
}
