import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/utils/camera_sidecar_config.dart';

void main() {
  const localhost = CameraSidecarConfig(
    enabled: true,
    baseUrl: 'http://127.0.0.1:8791',
    livePreviewEnabled: true,
    connectionMode: CameraConnectionMode.direct,
  );

  group('parseCameraConnectionMode', () {
    test('accepts pi and direct aliases', () {
      expect(parseCameraConnectionMode('pi'), CameraConnectionMode.pi);
      expect(parseCameraConnectionMode('LAN'), CameraConnectionMode.pi);
      expect(parseCameraConnectionMode('direct'), CameraConnectionMode.direct);
      expect(parseCameraConnectionMode('usb'), CameraConnectionMode.direct);
      expect(parseCameraConnectionMode('edsdk'), CameraConnectionMode.direct);
      expect(parseCameraConnectionMode(''), isNull);
      expect(parseCameraConnectionMode(null), isNull);
    });
  });

  group('isLoopbackCameraHost', () {
    test('detects loopback hosts', () {
      expect(isLoopbackCameraHost('127.0.0.1'), isTrue);
      expect(isLoopbackCameraHost('localhost'), isTrue);
      expect(isLoopbackCameraHost('192.168.2.50'), isFalse);
    });
  });

  group('CameraSidecarConfig.fromEnvironment', () {
    test('defaults to localhost sidecar enabled with live preview', () {
      final cfg = CameraSidecarConfig.fromEnvironment();
      expect(cfg.enabled, isTrue);
      expect(cfg.baseUrl, 'http://127.0.0.1:8791');
      expect(cfg.livePreviewEnabled, isTrue);
      expect(cfg.isConfigured, isTrue);
      expect(cfg.shouldShowLivePreview, isTrue);
      expect(cfg.connectionMode, CameraConnectionMode.direct);
    });
  });

  group('CameraSidecarConfig live preview URLs', () {
    test('live preview URLs empty when not configured', () {
      const cfg = CameraSidecarConfig(enabled: false, baseUrl: '');
      expect(cfg.livePreviewUrl, isEmpty);
      expect(cfg.previewFrameUrl, isEmpty);
    });

    test('live preview URLs join path prefixes', () {
      const withSlash = CameraSidecarConfig(
        enabled: true,
        baseUrl: 'http://127.0.0.1:8791/booth/',
        livePreviewEnabled: true,
      );
      expect(withSlash.livePreviewUrl, 'http://127.0.0.1:8791/booth/camera/live');
      expect(
        withSlash.previewFrameUrl,
        'http://127.0.0.1:8791/booth/camera/preview?download=1',
      );

      const withPrefix = CameraSidecarConfig(
        enabled: true,
        baseUrl: 'http://127.0.0.1:8791/booth',
        livePreviewEnabled: true,
      );
      expect(withPrefix.livePreviewUrl, 'http://127.0.0.1:8791/booth/camera/live');
    });
  });

  group('resolveCameraSidecarPath', () {
    test('empty or slash becomes root', () {
      expect(resolveCameraSidecarPath(null), '/');
      expect(resolveCameraSidecarPath(''), '/');
      expect(resolveCameraSidecarPath('/'), '/');
    });

    test('adds leading slash when missing', () {
      expect(resolveCameraSidecarPath('proxy'), '/proxy');
      expect(resolveCameraSidecarPath('/proxy/'), '/proxy/');
    });
  });

  group('buildCameraSidecarBaseUrl', () {
    test('omits root path and trailing slash', () {
      expect(
        buildCameraSidecarBaseUrl(host: '127.0.0.1', port: 8791),
        'http://127.0.0.1:8791',
      );
    });

    test('appends custom path prefix', () {
      expect(
        buildCameraSidecarBaseUrl(
          host: '127.0.0.1',
          port: 8791,
          path: '/sidecar/',
        ),
        'http://127.0.0.1:8791/sidecar',
      );
    });
  });

  group('resolveCameraSidecarConfig', () {
    test('returns direct localhost when settings null', () {
      final resolved = resolveCameraSidecarConfig(null, environment: localhost);
      expect(resolved.enabled, isTrue);
      expect(resolved.baseUrl, 'http://127.0.0.1:8791');
      expect(resolved.connectionMode, CameraConnectionMode.direct);
    });

    test('uses fromEnvironment when environment arg omitted', () {
      final resolved = resolveCameraSidecarConfig(null);
      final fromEnv = CameraSidecarConfig.fromEnvironment();
      expect(resolved.enabled, fromEnv.enabled);
      expect(resolved.baseUrl, fromEnv.baseUrl);
      expect(resolved.connectionMode, fromEnv.connectionMode);
    });

    test('explicit direct mode ignores Pi host', () {
      final resolved = resolveCameraSidecarConfig(
        AppSettingsModel(
          cameraEnabled: true,
          cameraConnectionMode: 'direct',
          cameraSidecarHost: '192.168.2.50',
          cameraSidecarPort: 8791,
          cameraLivePreviewEnabled: true,
        ),
        environment: localhost,
      );
      expect(resolved.connectionMode, CameraConnectionMode.direct);
      expect(resolved.baseUrl, 'http://127.0.0.1:8791');
      expect(resolved.enabled, isTrue);
      expect(resolved.livePreviewEnabled, isTrue);
    });

    test('explicit pi mode uses ZenAI host/port', () {
      final resolved = resolveCameraSidecarConfig(
        AppSettingsModel(
          cameraEnabled: true,
          cameraConnectionMode: 'pi',
          cameraSidecarHost: '192.168.2.50',
          cameraSidecarPort: 8791,
          cameraLivePreviewEnabled: true,
        ),
        environment: localhost,
      );
      expect(resolved.connectionMode, CameraConnectionMode.pi);
      expect(resolved.baseUrl, 'http://192.168.2.50:8791');
      expect(resolved.enabled, isTrue);
      expect(resolved.livePreviewEnabled, isTrue);
      expect(resolved.isPiConnection, isTrue);
    });

    test('infers pi from remote host when mode omitted', () {
      final resolved = resolveCameraSidecarConfig(
        AppSettingsModel(
          cameraEnabled: true,
          cameraSidecarHost: '172.16.4.128',
          cameraSidecarPort: 8791,
        ),
        environment: localhost,
      );
      expect(resolved.connectionMode, CameraConnectionMode.pi);
      expect(resolved.baseUrl, 'http://172.16.4.128:8791');
    });

    test('infers direct from loopback host when mode omitted', () {
      final resolved = resolveCameraSidecarConfig(
        AppSettingsModel(
          cameraEnabled: true,
          cameraSidecarHost: '127.0.0.1',
          cameraSidecarPort: 8791,
        ),
        environment: localhost,
      );
      expect(resolved.connectionMode, CameraConnectionMode.direct);
      expect(resolved.baseUrl, 'http://127.0.0.1:8791');
    });

    test('direct mode respects cameraEnabled false', () {
      final resolved = resolveCameraSidecarConfig(
        AppSettingsModel(
          cameraEnabled: false,
          cameraConnectionMode: 'direct',
        ),
        environment: localhost,
      );
      expect(resolved.enabled, isFalse);
      expect(resolved.isConfigured, isFalse);
    });

    test('pi mode disabled without host', () {
      final resolved = resolveCameraSidecarConfig(
        AppSettingsModel(
          cameraEnabled: true,
          cameraConnectionMode: 'pi',
        ),
        environment: localhost,
      );
      expect(resolved.enabled, isFalse);
      expect(resolved.connectionMode, CameraConnectionMode.pi);
    });
  });
}
