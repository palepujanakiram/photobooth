import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/utils/camera_sidecar_config.dart';

void main() {
  const env = CameraSidecarConfig(
    enabled: true,
    baseUrl: 'http://192.168.2.50:8791',
  );

  group('CameraSidecarConfig.fromEnvironment', () {
    test('uses dart-define defaults when not overridden', () {
      final cfg = CameraSidecarConfig.fromEnvironment();
      expect(cfg.enabled, isFalse);
      expect(cfg.baseUrl, 'http://192.168.2.50:8791');
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
        buildCameraSidecarBaseUrl(host: '10.0.0.5', port: 8791),
        'http://10.0.0.5:8791',
      );
    });

    test('appends custom path prefix', () {
      expect(
        buildCameraSidecarBaseUrl(
          host: '10.0.0.5',
          port: 8080,
          path: '/sidecar/',
        ),
        'http://10.0.0.5:8080/sidecar',
      );
    });
  });

  group('resolveCameraSidecarConfig', () {
    test('falls back to environment when settings null', () {
      final resolved = resolveCameraSidecarConfig(null, environment: env);
      expect(resolved, same(env));
    });

    test('uses fromEnvironment when environment arg omitted', () {
      final resolved = resolveCameraSidecarConfig(null);
      final fromEnv = CameraSidecarConfig.fromEnvironment();
      expect(resolved.enabled, fromEnv.enabled);
      expect(resolved.baseUrl, fromEnv.baseUrl);
    });

    test('falls back when settings omit camera fields', () {
      final resolved = resolveCameraSidecarConfig(
        AppSettingsModel(printerEnabled: true),
        environment: env,
      );
      expect(resolved, same(env));
    });

    test('settings win when camera fields present', () {
      final resolved = resolveCameraSidecarConfig(
        AppSettingsModel(
          cameraEnabled: true,
          cameraSidecarHost: ' 172.16.4.20 ',
          cameraSidecarPort: 8791,
          cameraSidecarPath: '/',
          cameraLivePreviewEnabled: true,
        ),
        environment: env,
      );
      expect(resolved.enabled, isTrue);
      expect(resolved.baseUrl, 'http://172.16.4.20:8791');
      expect(resolved.isConfigured, isTrue);
      expect(resolved.livePreviewEnabled, isTrue);
      expect(resolved.shouldShowLivePreview, isTrue);
    });

    test('live preview off by default when settings omit the flag', () {
      final resolved = resolveCameraSidecarConfig(
        AppSettingsModel(
          cameraEnabled: true,
          cameraSidecarHost: '172.16.4.20',
          cameraSidecarPort: 8791,
        ),
        environment: env,
      );
      expect(resolved.livePreviewEnabled, isFalse);
      expect(resolved.shouldShowLivePreview, isFalse);
    });

    test('live preview alone counts as settings-present', () {
      final resolved = resolveCameraSidecarConfig(
        AppSettingsModel(cameraLivePreviewEnabled: true),
        environment: env,
      );
      expect(resolved.enabled, isFalse);
      expect(resolved.livePreviewEnabled, isTrue);
      expect(resolved.shouldShowLivePreview, isFalse);
    });

    test('disabled when cameraEnabled false even with host', () {
      final resolved = resolveCameraSidecarConfig(
        AppSettingsModel(
          cameraEnabled: false,
          cameraSidecarHost: '172.16.4.20',
          cameraSidecarPort: 8791,
        ),
        environment: env,
      );
      expect(resolved.enabled, isFalse);
      expect(resolved.isConfigured, isFalse);
    });

    test('disabled when enabled but host empty', () {
      final resolved = resolveCameraSidecarConfig(
        AppSettingsModel(
          cameraEnabled: true,
          cameraSidecarHost: '  ',
          cameraSidecarPort: 8791,
        ),
        environment: env,
      );
      expect(resolved.enabled, isFalse);
      expect(resolved.baseUrl, isEmpty);
    });

    test('defaults invalid port to sidecar default', () {
      final resolved = resolveCameraSidecarConfig(
        AppSettingsModel(
          cameraEnabled: true,
          cameraSidecarHost: '10.0.0.1',
          cameraSidecarPort: 0,
        ),
        environment: env,
      );
      expect(resolved.baseUrl, 'http://10.0.0.1:$kCameraSidecarDefaultPort');
    });

    test('uses custom path from settings', () {
      final resolved = resolveCameraSidecarConfig(
        AppSettingsModel(
          cameraEnabled: true,
          cameraSidecarHost: '10.0.0.1',
          cameraSidecarPort: 8080,
          cameraSidecarPath: 'cam',
        ),
        environment: env,
      );
      expect(resolved.baseUrl, 'http://10.0.0.1:8080/cam');
    });

    test('cameraEnabled alone without host is settings-present but not configured',
        () {
      final resolved = resolveCameraSidecarConfig(
        AppSettingsModel(cameraEnabled: false),
        environment: env,
      );
      expect(resolved.enabled, isFalse);
      expect(identical(resolved, env), isFalse);
    });
  });
}
