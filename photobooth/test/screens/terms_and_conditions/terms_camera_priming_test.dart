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

    test('invokes ensureCanonUsbPermission before camera permission', () async {
      final order = <String>[];
      await runTermsCameraPriming(
        ensurePermission: () async {
          order.add('camera');
          return true;
        },
        preloadCameras: () async {},
        classifyDevice: () async => AppDeviceType.androidTv,
        startPrewarm: (_) async {},
        hasOpenableCamera: (_) => true,
        isCameraPlatform: true,
        ensureCanonUsbPermission: () async {
          order.add('canon_usb');
          return true;
        },
      );
      expect(order, ['canon_usb', 'camera']);
    });

    test('invokes ensureCanonUsbPermission when provided', () async {
      var usbEnsured = false;
      final result = await runTermsCameraPriming(
        ensurePermission: () async => true,
        preloadCameras: () async {},
        classifyDevice: () async => AppDeviceType.androidTv,
        startPrewarm: (_) async {},
        hasOpenableCamera: (_) => true,
        isCameraPlatform: true,
        ensureCanonUsbPermission: () async {
          usbEnsured = true;
          return true;
        },
      );

      expect(usbEnsured, isTrue);
      expect(result.phase, TermsCameraPrimingPhase.ready);
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

    test('returns ready when CameraX is empty but sidecar is healthy', () async {
      var sidecarProbed = false;
      final result = await runTermsCameraPriming(
        ensurePermission: () async => true,
        preloadCameras: () async {},
        classifyDevice: () async => AppDeviceType.androidTv,
        startPrewarm: (_) async {},
        hasOpenableCamera: (_) => false,
        isCameraPlatform: true,
        probeAttachedUvc: () async => false,
        probeSidecarHealthy: () async {
          sidecarProbed = true;
          return true;
        },
      );

      expect(result.phase, TermsCameraPrimingPhase.ready);
      expect(sidecarProbed, isTrue);
      expect(result.allowsContinue, isTrue);
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
        probeSidecarHealthy: () async => false,
      );

      expect(result.phase, TermsCameraPrimingPhase.failed);
      expect(result.allowsContinue, isFalse);
    });

    test('returns ready when post-preload check throws but UVC is attached',
        () async {
      final result = await runTermsCameraPriming(
        ensurePermission: () async => true,
        preloadCameras: () async {},
        classifyDevice: () async => AppDeviceType.androidTv,
        startPrewarm: (_) async {},
        hasOpenableCamera: (_) => throw StateError('camera check failed'),
        isCameraPlatform: true,
        probeAttachedUvc: () async => true,
      );

      expect(result.phase, TermsCameraPrimingPhase.ready);
      expect(result.allowsContinue, isTrue);
    });
  });

  group('termsHasUsableCaptureSource', () {
    test('accepts CameraX, UVC, or sidecar', () {
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
          hasSidecarCamera: true,
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

  group('TermsCanonPrimingMemo', () {
    setUp(TermsCanonPrimingMemo.reset);
    tearDown(TermsCanonPrimingMemo.reset);

    test('starts unprimed and remembers a ready pass', () {
      expect(TermsCanonPrimingMemo.isPrimed, isFalse);
      TermsCanonPrimingMemo.markPrimed();
      expect(TermsCanonPrimingMemo.isPrimed, isTrue);
      TermsCanonPrimingMemo.reset();
      expect(TermsCanonPrimingMemo.isPrimed, isFalse);
    });
  });

  group('canSkipTermsPrimingOnReentry', () {
    test('never skips the first visit', () async {
      var probed = false;
      final skip = await canSkipTermsPrimingOnReentry(
        primedBefore: false,
        probeStillReady: () async {
          probed = true;
          return true;
        },
      );
      expect(skip, isFalse);
      expect(probed, isFalse, reason: 'no live probe before a first pass');
    });

    test('skips when a primed booth is still ready', () async {
      expect(
        await canSkipTermsPrimingOnReentry(
          primedBefore: true,
          probeStillReady: () async => true,
        ),
        isTrue,
      );
    });

    test('re-primes when the camera left between guests', () async {
      expect(
        await canSkipTermsPrimingOnReentry(
          primedBefore: true,
          probeStillReady: () async => false,
        ),
        isFalse,
      );
    });

    test('re-primes when the probe throws', () async {
      expect(
        await canSkipTermsPrimingOnReentry(
          primedBefore: true,
          probeStillReady: () async => throw StateError('channel down'),
        ),
        isFalse,
      );
    });
  });

  group('shouldShowCanonUsbPrimingHint', () {
    test('shows only while a Canon booth still needs the grant', () {
      expect(
        shouldShowCanonUsbPrimingHint(
          isCanonUsbBooth: true,
          permissionPending: true,
        ),
        isTrue,
      );
    });

    test('hides once the grant is held', () {
      expect(
        shouldShowCanonUsbPrimingHint(
          isCanonUsbBooth: true,
          permissionPending: false,
        ),
        isFalse,
      );
    });

    test('hides on booths that never touch USB', () {
      expect(
        shouldShowCanonUsbPrimingHint(
          isCanonUsbBooth: false,
          permissionPending: true,
        ),
        isFalse,
      );
    });
  });
}
