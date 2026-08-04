import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/capture_session_kind.dart';
import 'package:photobooth/utils/classic_capture_intent.dart';
import 'package:photobooth/utils/classic_shot_mode.dart';

import '../fixtures/theme_fixtures.dart';

void main() {
  tearDown(ClassicCaptureIntent.resetForTests);

  test('beginClassic stores kind + theme; clear wipes both', () {
    ClassicCaptureIntent.beginClassic(
      mode: ClassicShotMode.single6x4,
      theme: sampleTheme('strip'),
    );
    expect(ClassicCaptureIntent.peekKind(), CaptureSessionKind.classicOneShot);
    expect(ClassicCaptureIntent.peekTheme()?.id, 'strip');

    ClassicCaptureIntent.clear();
    expect(ClassicCaptureIntent.peekKind(), isNull);
    expect(ClassicCaptureIntent.peekTheme(), isNull);
  });

  test('beginClassic four-shot maps to classicFourShot', () {
    ClassicCaptureIntent.beginClassic(
      mode: ClassicShotMode.fourShot,
      theme: sampleTheme('strip4'),
    );
    expect(ClassicCaptureIntent.peekKind(), CaptureSessionKind.classicFourShot);
    expect(ClassicCaptureIntent.peekTheme()?.id, 'strip4');
  });

  test('beginClassic overwrites previous theme backup', () {
    ClassicCaptureIntent.beginClassic(
      mode: ClassicShotMode.single6x4,
      theme: sampleTheme('a'),
    );
    ClassicCaptureIntent.beginClassic(
      mode: ClassicShotMode.fourShot,
      theme: sampleTheme('b'),
    );
    expect(ClassicCaptureIntent.peekKind(), CaptureSessionKind.classicFourShot);
    expect(ClassicCaptureIntent.peekTheme()?.id, 'b');
  });
}
