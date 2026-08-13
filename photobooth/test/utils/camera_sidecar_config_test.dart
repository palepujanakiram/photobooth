import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/utils/camera_sidecar_config.dart';

void main() {
  const localhost = CameraSidecarConfig(
    enabled: true,
    baseUrl: 'http://127.0.0.1:8791',
    livePreviewEnabled: true,
  );

  group('CameraSidecarConfig.fromEnvironment', () {
    test('defaults to localhost sidecar enabled with live preview', () {
      final cfg = CameraSidecarConfig.fromEnvironment();
      expect(cfg.enabled, isTrue);
      expect(cfg.baseUrl, 'http://127.0.0.1:8791');
      expect(cfg.livePreviewEnabled, isTrue);
      expect(cfg.isConfigured, isTrue);
      expect(cfg.shouldShowLivePreview, isTrue);
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
    test('returns environment when settings null', () {
      final resolved = resolveCameraSidecarConfig(null, environment: localhost);
      expect(resolved, same(localhost));
    });

    test('uses fromEnvironment when environment arg omitted', () {
      final resolved = resolveCameraSidecarConfig(null);
      final fromEnv = CameraSidecarConfig.fromEnvironment();
      expect(resolved.enabled, fromEnv.enabled);
      expect(resolved.baseUrl, fromEnv.baseUrl);
    });

    test('admin settings are ignored — always returns environment', () {
      // Admin settings for Pi host/port/path must not override localhost config.
      final resolved = resolveCameraSidecarConfig(
        AppSettingsModel(
          cameraEnabled: true,
          cameraSidecarHost: '192.168.2.50',
          cameraSidecarPort: 8791,
          cameraLivePreviewEnabled: true,
        ),
        environment: localhost,
      );
      expect(resolved, same(localhost));
      expect(resolved.baseUrl, 'http://127.0.0.1:8791');
    });

    test('admin settings with camera disabled still returns environment', () {
      final resolved = resolveCameraSidecarConfig(
        AppSettingsModel(cameraEnabled: false),
        environment: localhost,
      );
      expect(resolved, same(localhost));
    });
  });
}
