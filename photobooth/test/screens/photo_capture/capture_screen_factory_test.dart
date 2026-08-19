import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/strip_models.dart';
import 'package:photobooth/screens/photo_capture/capture_screen_factory.dart';
import 'package:photobooth/screens/photo_capture/direct_ptp_capture_view.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_view.dart';
import 'package:photobooth/screens/theme_selection/theme_model.dart';
import 'package:photobooth/utils/camera_source_config.dart';
import 'package:photobooth/utils/capture_session_kind.dart';
import 'package:photobooth/utils/classic_shot_mode.dart';
import 'package:photobooth/utils/route_args.dart';

ThemeModel _theme() => const ThemeModel(
      id: 't1',
      categoryId: 'c1',
      name: 'Theme',
      description: '',
      promptText: '',
    );

CaptureRouteArgs _classicArgs({
  required int total,
  ClassicShotMode? mode,
}) =>
    CaptureRouteArgs(
      returnPhotoOnly: true,
      multiShotTotal: total,
      flashbackTheme: _theme(),
      classicShotMode: mode,
    );

void main() {
  group('buildCaptureScreen', () {
    test('device source builds the CameraX capture screen', () {
      final screen = buildCaptureScreen(
        sessionKind: CaptureSessionKind.fotoZen,
        source: CameraSource.device,
      );
      expect(screen, isA<PhotoCaptureScreen>());
    });

    test('direct PTP source builds the native-backed capture screen', () {
      // The reason this factory exists: POSE is entered from four places, and
      // three construct the screen directly. If this branch is ever bypassed,
      // a DSLR booth silently opens CameraX and hangs on a box with no camera.
      final screen = buildCaptureScreen(
        sessionKind: CaptureSessionKind.fotoZen,
        source: CameraSource.directPtp,
      );
      expect(screen, isA<DirectPtpCaptureScreen>());
    });

    test('uvc and sidecar sources keep the existing Flutter screen', () {
      expect(
        buildCaptureScreen(
          sessionKind: CaptureSessionKind.fotoZen,
          source: CameraSource.uvc,
        ),
        isA<PhotoCaptureScreen>(),
      );
      expect(
        buildCaptureScreen(
          sessionKind: CaptureSessionKind.fotoZen,
          source: CameraSource.sidecar,
        ),
        isA<PhotoCaptureScreen>(),
      );
    });

    test('session kind and args are forwarded to the direct-PTP screen', () {
      final args = _classicArgs(total: kStripShotCount);
      final screen = buildCaptureScreen(
        sessionKind: CaptureSessionKind.classicFourShot,
        captureArgs: args,
        source: CameraSource.directPtp,
      ) as DirectPtpCaptureScreen;
      expect(screen.sessionKind, CaptureSessionKind.classicFourShot);
      expect(screen.captureArgs, same(args));
    });

    test('session kind and args are forwarded to the Flutter screen', () {
      final args = _classicArgs(total: kStripShotCount);
      final screen = buildCaptureScreen(
        sessionKind: CaptureSessionKind.classicOneShot,
        captureArgs: args,
        source: CameraSource.device,
      ) as PhotoCaptureScreen;
      expect(screen.sessionKind, CaptureSessionKind.classicOneShot);
      expect(screen.captureArgs, same(args));
    });

    test('the key is forwarded so route remounts stay distinguishable', () {
      const key = ValueKey<String>('pose-1');
      final screen = buildCaptureScreen(
        key: key,
        sessionKind: CaptureSessionKind.fotoZen,
        source: CameraSource.device,
      );
      expect(screen.key, key);
    });

    test('without an override it falls back to the configured source', () {
      // No CAMERA_SOURCE define in tests, so this must be the device camera —
      // i.e. existing builds are untouched by the direct-PTP work.
      expect(
        buildCaptureScreen(sessionKind: CaptureSessionKind.fotoZen),
        isA<PhotoCaptureScreen>(),
      );
    });
  });

  group('captureSessionKindFor', () {
    test('null args mean the AI single-shot flow', () {
      expect(captureSessionKindFor(null), CaptureSessionKind.fotoZen);
    });

    test('an explicit shot mode wins over the inferred totals', () {
      // classicShotMode survives Map round-trips better than the total alone,
      // so it is the more trustworthy signal when both are present.
      expect(
        captureSessionKindFor(
          _classicArgs(total: 1, mode: ClassicShotMode.fourShot),
        ),
        CaptureSessionKind.classicFourShot,
      );
      expect(
        captureSessionKindFor(
          _classicArgs(total: kStripShotCount, mode: ClassicShotMode.single6x4),
        ),
        CaptureSessionKind.classicOneShot,
      );
    });

    test('a four-shot strip is inferred from the totals', () {
      expect(
        captureSessionKindFor(_classicArgs(total: kStripShotCount)),
        CaptureSessionKind.classicFourShot,
      );
    });

    test('a single 6x4 is inferred from the totals', () {
      expect(
        captureSessionKindFor(_classicArgs(total: 1)),
        CaptureSessionKind.classicOneShot,
      );
    });

    test('args that describe no strip fall back to FotoZen', () {
      expect(
        captureSessionKindFor(const CaptureRouteArgs()),
        CaptureSessionKind.fotoZen,
      );
    });
  });
}
