import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/terms_and_conditions/terms_camera_priming.dart';
import 'package:photobooth/utils/app_device_type.dart';

void main() {
  group('runTermsCameraPriming', () {
    test('skips priming on non-camera platforms', () async {
      final result = await runTermsCameraPriming(
        ensurePermission: () async => false,
        preloadCameras: () async {},
        classifyDevice: () async => AppDeviceType.androidTablet,
        startPrewarm: (_) async {},
        hasOpenableCamera: (_) => true,
        isCameraPlatform: false,
      );

      expect(result.phase, TermsCameraPrimingPhase.skipped);
      expect(result.allowsContinue, isTrue);
    });

    test('returns permissionDenied when permission is not granted', () async {
      final result = await runTermsCameraPriming(
        ensurePermission: () async => false,
        preloadCameras: () async {},
        classifyDevice: () async => AppDeviceType.androidTablet,
        startPrewarm: (_) async {},
        hasOpenableCamera: (_) => true,
        isCameraPlatform: true,
      );

      expect(result.phase, TermsCameraPrimingPhase.permissionDenied);
      expect(result.allowsContinue, isFalse);
    });

    test('returns noneFound when enumeration finds no openable camera', () async {
      var prewarmStarted = false;
      var uvcProbed = false;
      final result = await runTermsCameraPriming(
        ensurePermission: () async => true,
        preloadCameras: () async {},
        classifyDevice: () async => AppDeviceType.androidTablet,
        startPrewarm: (_) async => prewarmStarted = true,
        hasOpenableCamera: (_) => false,
        isCameraPlatform: true,
        probeAttachedUvc: () async {
          uvcProbed = true;
          return false;
        },
      );

      expect(result.phase, TermsCameraPrimingPhase.noneFound);
      expect(prewarmStarted, isFalse);
      expect(uvcProbed, isTrue);
      expect(result.allowsContinue, isFalse);
    });

    test('returns ready when CameraX is empty but UVC is attached', () async {
      var prewarmStarted = false;
      final result = await runTermsCameraPriming(
        ensurePermission: () async => true,
        preloadCameras: () async {},
        classifyDevice: () async => AppDeviceType.androidTv,
        startPrewarm: (_) async => prewarmStarted = true,
        hasOpenableCamera: (_) => false,
        isCameraPlatform: true,
        probeAttachedUvc: () async => true,
      );

      expect(result.phase, TermsCameraPrimingPhase.ready);
      expect(prewarmStarted, isFalse);
      expect(result.allowsContinue, isTrue);
    });

    test('returns ready when CameraX preload throws but UVC is attached',
        () async {
      final result = await runTermsCameraPriming(
        ensurePermission: () async => true,
        preloadCameras: () async => throw StateError('enumerate failed'),
        classifyDevice: () async => AppDeviceType.androidTv,
        startPrewarm: (_) async {},
        hasOpenableCamera: (_) => false,
        isCameraPlatform: true,
        probeAttachedUvc: () async => true,
      );

      expect(result.phase, TermsCameraPrimingPhase.ready);
    });

    test('starts prewarm and returns ready when a camera is available', () async {
      AppDeviceType? prewarmType;
      var uvcProbed = false;
      final result = await runTermsCameraPriming(
        ensurePermission: () async => true,
        preloadCameras: () async {},
        classifyDevice: () async => AppDeviceType.androidTv,
        startPrewarm: (deviceType) async => prewarmType = deviceType,
        hasOpenableCamera: (_) => true,
        isCameraPlatform: true,
        probeAttachedUvc: () async {
          uvcProbed = true;
          return false;
        },
      );

      expect(result.phase, TermsCameraPrimingPhase.ready);
      expect(prewarmType, AppDeviceType.androidTv);
      expect(uvcProbed, isFalse);
      expect(result.allowsContinue, isTrue);
    });

    test('returns ready when classifyDevice fails but cameras exist', () async {
      final result = await runTermsCameraPriming(
        ensurePermission: () async => true,
        preloadCameras: () async {},
        classifyDevice: () async => throw StateError('no context'),
        startPrewarm: (_) async {},
        hasOpenableCamera: (_) => true,
        isCameraPlatform: true,
      );

      expect(result.phase, TermsCameraPrimingPhase.ready);
    });

    test('returns failed when preloadCameras throws and no UVC', () async {
      final result = await runTermsCameraPriming(
        ensurePermission: () async => true,
        preloadCameras: () async => throw StateError('enumerate failed'),
        classifyDevice: () async => AppDeviceType.androidTablet,
        startPrewarm: (_) async {},
        hasOpenableCamera: (_) => true,
        isCameraPlatform: true,
        probeAttachedUvc: () async => false,
      );

      expect(result.phase, TermsCameraPrimingPhase.failed);
      expect(result.allowsContinue, isFalse);
    });
  });

  group('termsHasUsableCaptureSource', () {
    test('accepts CameraX or UVC', () {
      expect(
        termsHasUsableCaptureSource(
          hasOpenableCameraX: true,
          hasAttachedUvc: false,
        ),
        isTrue,
      );
      expect(
        termsHasUsableCaptureSource(
          hasOpenableCameraX: false,
          hasAttachedUvc: true,
        ),
        isTrue,
      );
      expect(
        termsHasUsableCaptureSource(
          hasOpenableCameraX: false,
          hasAttachedUvc: false,
        ),
        isFalse,
      );
    });
  });

  group('termsCameraPrimingAllowsContinue', () {
    test('allows skipped and ready without upload', () {
      expect(
        termsCameraPrimingAllowsContinue(
          phase: TermsCameraPrimingPhase.skipped,
        ),
        isTrue,
      );
      expect(
        termsCameraPrimingAllowsContinue(
          phase: TermsCameraPrimingPhase.ready,
        ),
        isTrue,
      );
    });

    test('blocks noneFound/permissionDenied/failed without upload', () {
      expect(
        termsCameraPrimingAllowsContinue(
          phase: TermsCameraPrimingPhase.noneFound,
        ),
        isFalse,
      );
      expect(
        termsCameraPrimingAllowsContinue(
          phase: TermsCameraPrimingPhase.permissionDenied,
        ),
        isFalse,
      );
      expect(
        termsCameraPrimingAllowsContinue(
          phase: TermsCameraPrimingPhase.failed,
        ),
        isFalse,
      );
    });

    test('still blocks detecting even when upload is allowed', () {
      expect(
        termsCameraPrimingAllowsContinue(
          phase: TermsCameraPrimingPhase.detecting,
          photoUploadAllowed: true,
        ),
        isFalse,
      );
    });

    test('allows camera-failure phases when photo upload is allowed', () {
      expect(
        termsCameraPrimingAllowsContinue(
          phase: TermsCameraPrimingPhase.noneFound,
          photoUploadAllowed: true,
        ),
        isTrue,
      );
      expect(
        termsCameraPrimingAllowsContinue(
          phase: TermsCameraPrimingPhase.permissionDenied,
          photoUploadAllowed: true,
        ),
        isTrue,
      );
      expect(
        termsCameraPrimingAllowsContinue(
          phase: TermsCameraPrimingPhase.failed,
          photoUploadAllowed: true,
        ),
        isTrue,
      );
    });
  });
}
