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
      final result = await runTermsCameraPriming(
        ensurePermission: () async => true,
        preloadCameras: () async {},
        classifyDevice: () async => AppDeviceType.androidTablet,
        startPrewarm: (_) async => prewarmStarted = true,
        hasOpenableCamera: (_) => false,
        isCameraPlatform: true,
      );

      expect(result.phase, TermsCameraPrimingPhase.noneFound);
      expect(prewarmStarted, isFalse);
      expect(result.allowsContinue, isFalse);
    });

    test('starts prewarm and returns ready when a camera is available', () async {
      AppDeviceType? prewarmType;
      final result = await runTermsCameraPriming(
        ensurePermission: () async => true,
        preloadCameras: () async {},
        classifyDevice: () async => AppDeviceType.androidTv,
        startPrewarm: (deviceType) async => prewarmType = deviceType,
        hasOpenableCamera: (_) => true,
        isCameraPlatform: true,
      );

      expect(result.phase, TermsCameraPrimingPhase.ready);
      expect(prewarmType, AppDeviceType.androidTv);
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

    test('returns failed when preloadCameras throws', () async {
      final result = await runTermsCameraPriming(
        ensurePermission: () async => true,
        preloadCameras: () async => throw StateError('enumerate failed'),
        classifyDevice: () async => AppDeviceType.androidTablet,
        startPrewarm: (_) async {},
        hasOpenableCamera: (_) => true,
        isCameraPlatform: true,
      );

      expect(result.phase, TermsCameraPrimingPhase.failed);
      expect(result.allowsContinue, isFalse);
    });
  });
}
