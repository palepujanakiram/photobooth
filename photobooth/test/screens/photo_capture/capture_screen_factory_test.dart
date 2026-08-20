import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/screens/photo_capture/capture_screen_factory.dart';
import 'package:photobooth/screens/photo_capture/capture_screen_router.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_view.dart';
import 'package:photobooth/screens/theme_selection/theme_model.dart';
import 'package:photobooth/utils/capture_session_kind.dart';
import 'package:photobooth/utils/classic_shot_mode.dart';
import 'package:photobooth/utils/route_args.dart';

void main() {
  const theme = ThemeModel(
    id: 't1',
    categoryId: 'c1',
    name: 'Test theme',
    description: 'd',
    promptText: 'p',
  );

  tearDown(() {
    directPtpHardwareProbeOverride = null;
  });

  group('buildCaptureScreen', () {
    test('returns router when ZenAI mode is direct_ptp', () {
      final screen = buildCaptureScreen(
        sessionKind: CaptureSessionKind.fotoZen,
        settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
      );
      expect(screen, isA<CaptureScreenRouter>());
    });

    test('keeps the Flutter capture screen for USB EDSDK / Pi', () {
      final screen = buildCaptureScreen(
        sessionKind: CaptureSessionKind.fotoZen,
        settings: AppSettingsModel(cameraConnectionMode: 'direct'),
      );
      expect(screen, isA<PhotoCaptureScreen>());
    });

    testWidgets('a context without AppSettingsManager stays on Flutter capture',
        (tester) async {
      late Widget screen;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              screen = buildCaptureScreen(
                sessionKind: CaptureSessionKind.fotoZen,
                context: context,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(screen, isA<PhotoCaptureScreen>());
    });
  });

  group('captureSessionKindFor', () {
    test('absent args are FotoZen', () {
      expect(captureSessionKindFor(null), CaptureSessionKind.fotoZen);
    });

    test('classicShotMode wins when present', () {
      expect(
        captureSessionKindFor(
          const CaptureRouteArgs(classicShotMode: ClassicShotMode.fourShot),
        ),
        CaptureSessionKind.classicFourShot,
      );
      expect(
        captureSessionKindFor(
          const CaptureRouteArgs(classicShotMode: ClassicShotMode.single6x4),
        ),
        CaptureSessionKind.classicOneShot,
      );
    });

    test('flashback four-shot without classicShotMode is classicFourShot', () {
      expect(
        captureSessionKindFor(
          const CaptureRouteArgs(
            returnPhotoOnly: true,
            multiShotTotal: 4,
            flashbackTheme: theme,
          ),
        ),
        CaptureSessionKind.classicFourShot,
      );
    });

    test('flashback single 6x4 without classicShotMode is classicOneShot', () {
      expect(
        captureSessionKindFor(
          const CaptureRouteArgs(
            returnPhotoOnly: true,
            multiShotTotal: 1,
            flashbackTheme: theme,
          ),
        ),
        CaptureSessionKind.classicOneShot,
      );
    });

    test('plain capture args stay FotoZen', () {
      expect(
        captureSessionKindFor(const CaptureRouteArgs()),
        CaptureSessionKind.fotoZen,
      );
    });
  });

  group('buildCaptureScreen forwarding', () {
    const args = CaptureRouteArgs(
      returnPhotoOnly: true,
      multiShotTotal: 4,
      flashbackTheme: theme,
      classicShotMode: ClassicShotMode.fourShot,
    );

    test('direct_ptp routes through CaptureScreenRouter with args', () {
      final screen = buildCaptureScreen(
        sessionKind: CaptureSessionKind.classicFourShot,
        captureArgs: args,
        settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
      ) as CaptureScreenRouter;
      expect(screen.sessionKind, CaptureSessionKind.classicFourShot);
      expect(screen.captureArgs, same(args));
    });

    test('session kind and args reach the Flutter screen', () {
      final screen = buildCaptureScreen(
        sessionKind: CaptureSessionKind.classicOneShot,
        captureArgs: args,
        settings: AppSettingsModel(cameraConnectionMode: 'pi'),
      ) as PhotoCaptureScreen;
      expect(screen.sessionKind, CaptureSessionKind.classicOneShot);
      expect(screen.captureArgs, same(args));
    });

    test('the key is forwarded so route remounts stay distinguishable', () {
      const key = ValueKey<String>('pose-1');
      final screen = buildCaptureScreen(
        key: key,
        sessionKind: CaptureSessionKind.fotoZen,
        settings: AppSettingsModel(cameraConnectionMode: 'pi'),
      );
      expect(screen.key, key);
    });
  });
}
