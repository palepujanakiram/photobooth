import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photobooth/services/local_camera_service.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:photobooth/utils/camera_sidecar_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('CameraSidecarConfig', () {
    test('envFlagForTesting accepts true-like values', () {
      expect(CameraSidecarConfig.envFlagForTesting('true'), isTrue);
      expect(CameraSidecarConfig.envFlagForTesting('1'), isTrue);
      expect(CameraSidecarConfig.envFlagForTesting('yes'), isTrue);
      expect(CameraSidecarConfig.envFlagForTesting(''), isFalse);
      expect(CameraSidecarConfig.envFlagForTesting('false'), isFalse);
    });

    test('isConfigured requires enabled and baseUrl', () {
      expect(
        const CameraSidecarConfig(
          enabled: true,
          baseUrl: 'http://192.168.2.50:8791',
        ).isConfigured,
        isTrue,
      );
      expect(
        const CameraSidecarConfig(
          enabled: false,
          baseUrl: 'http://192.168.2.50:8791',
        ).isConfigured,
        isFalse,
      );
    });
  });

  group('LocalCameraService', () {
    const config = CameraSidecarConfig(
      enabled: true,
      baseUrl: 'http://192.168.2.50:8791',
    );

    test('setForceLivePreview enables shouldShowLivePreview', () {
      final service = LocalCameraService(
        config: config,
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(service.shouldShowLivePreview, isFalse);
      service.setForceLivePreview(true);
      expect(service.shouldShowLivePreview, isTrue);
      service.setForceLivePreview(false);
      expect(service.shouldShowLivePreview, isFalse);
      service.dispose();
    });

    test('reports connection mode and host label', () {
      final direct = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: true,
          baseUrl: 'http://127.0.0.1:8791',
          connectionMode: CameraConnectionMode.direct,
        ),
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(direct.isDirectConnection, isTrue);
      expect(direct.isPiConnection, isFalse);
      expect(direct.baseUrlLabel, '127.0.0.1:8791');
      expect(direct.recentlyHealthy, isFalse);
      direct.dispose();

      final pi = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: true,
          baseUrl: 'http://172.16.4.128',
          connectionMode: CameraConnectionMode.pi,
        ),
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(pi.isPiConnection, isTrue);
      expect(pi.isDirectConnection, isFalse);
      expect(pi.baseUrlLabel, '172.16.4.128:8791');
      pi.dispose();

      final invalid = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: true,
          baseUrl: '::not-a-uri::',
        ),
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(invalid.baseUrlLabel, '::not-a-uri::');
      invalid.dispose();
    });

    test('recentlyHealthy after a successful health check', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'ok': true, 'connected': true}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = LocalCameraService(config: config, client: client);
      expect(service.recentlyHealthy, isFalse);
      expect(await service.isHealthy(), isTrue);
      expect(service.recentlyHealthy, isTrue);
      service.dispose();
    });

    test('markRuntimeUnavailable stops preview and capture config', () {
      final service = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: true,
          baseUrl: 'http://127.0.0.1:8791',
          livePreviewEnabled: true,
        ),
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(service.isConfigured, isTrue);
      expect(service.shouldShowLivePreview, isTrue);
      service.markRuntimeUnavailable();
      expect(service.isConfigured, isFalse);
      expect(service.shouldShowLivePreview, isFalse);
      service.setForceLivePreview(true);
      expect(service.shouldShowLivePreview, isFalse);
      service.dispose();
    });

    test('prepareStill posts /camera/prepare-still', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/camera/prepare-still');
        return http.Response(
          jsonEncode({'ok': true, 'prepared': true, 'ms': 12}),
          200,
        );
      });
      final service = LocalCameraService(config: config, client: client);
      await service.prepareStill();
      service.dispose();
    });

    test('prepareStill throws when not configured', () async {
      final service = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: false,
          baseUrl: 'http://192.168.2.50:8791',
        ),
      );
      await expectLater(service.prepareStill(), throwsStateError);
      service.dispose();
    });

    test('prepareStill throws on HTTP error status', () async {
      final client = MockClient((request) async {
        return http.Response('busy', 503);
      });
      final service = LocalCameraService(config: config, client: client);
      await expectLater(
        service.prepareStill(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('prepare-still failed'),
          ),
        ),
      );
      service.dispose();
    });

    test('isHealthy true when connected', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/health');
        expect(request.headers.containsKey('X-Camera-Token'), isFalse);
        return http.Response(
          jsonEncode({'ok': true, 'connected': true}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = LocalCameraService(config: config, client: client);
      expect(await service.isHealthy(), isTrue);
      service.dispose();
    });

    test('isHealthy false when disconnected', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'ok': true, 'connected': false}),
          200,
        );
      });
      final service = LocalCameraService(config: config, client: client);
      expect(await service.isHealthy(), isFalse);
      service.dispose();
    });

    test('sidecarHttpBodyLooksLikeJpeg detects JPEG SOI', () {
      expect(sidecarHttpBodyLooksLikeJpeg([0xff, 0xd8, 0xff, 0xd9]), isTrue);
      expect(sidecarHttpBodyLooksLikeJpeg([0xff, 0xd8]), isFalse);
      expect(sidecarHttpBodyLooksLikeJpeg([0x49, 0x49, 0x2a, 0x00]), isFalse);
      expect(sidecarHttpBodyLooksLikeJpeg([]), isFalse);
    });

    test('capture returns jpeg bytes and sends download query', () async {
      final jpeg = <int>[0xff, 0xd8, 0xff, 0xd9, ...List.filled(100, 1)];
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/camera/capture');
        expect(request.url.queryParameters['download'], '1');
        expect(request.url.queryParameters['maxLongEdge'], '1920');
        expect(request.url.queryParameters['jpegQuality'], '85');
        expect(request.url.queryParameters['resumeLiveView'], '1');
        expect(request.headers.containsKey('X-Camera-Token'), isFalse);
        return http.Response.bytes(jpeg, 200, headers: {
          'content-type': 'image/jpeg',
        });
      });
      final service = LocalCameraService(config: config, client: client);
      final bytes = await service.capture();
      expect(bytes.first, 0xff);
      expect(bytes.length, jpeg.length);
      service.dispose();
    });

    test('capture forwards custom maxLongEdge and jpegQuality', () async {
      final client = MockClient((request) async {
        expect(request.url.queryParameters['maxLongEdge'], '1280');
        expect(request.url.queryParameters['jpegQuality'], '70');
        expect(request.url.queryParameters['resumeLiveView'], '1');
        return http.Response.bytes([0xff, 0xd8, 0xff, 0xd9], 200);
      });
      final service = LocalCameraService(config: config, client: client);
      await service.capture(maxLongEdge: 1280, jpegQuality: 70);
      service.dispose();
    });

    test('capture can disable resumeLiveView', () async {
      final client = MockClient((request) async {
        expect(request.url.queryParameters['resumeLiveView'], '0');
        return http.Response.bytes([0xff, 0xd8, 0xff, 0xd9], 200);
      });
      final service = LocalCameraService(config: config, client: client);
      await service.capture(resumeLiveView: false);
      service.dispose();
    });

    test('capture logs progress while waiting', () async {
      final client = MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return http.Response.bytes([0xff, 0xd8, 0xff, 0xd9], 200);
      });
      final service = LocalCameraService(
        config: config,
        client: client,
        captureProgressInterval: const Duration(milliseconds: 5),
      );
      final bytes = await service.capture();
      expect(bytes.first, 0xff);
      service.dispose();
    });

    test('capture rethrows on timeout', () async {
      final client = MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return http.Response.bytes([0xff, 0xd8, 0xff, 0xd9], 200);
      });
      final service = LocalCameraService(
        config: config,
        client: client,
        captureTimeout: const Duration(milliseconds: 1),
      );
      await expectLater(service.capture(), throwsA(isA<TimeoutException>()));
      service.dispose();
    });

    test('capture throws when body is not JPEG', () async {
      final client = MockClient((request) async {
        return http.Response.bytes(
          [0x49, 0x49, 0x2a, 0x00, ...List.filled(80, 0)],
          200,
          headers: {'content-type': 'image/jpeg'},
        );
      });
      final service = LocalCameraService(config: config, client: client);
      await expectLater(
        service.capture(),
        throwsA(
          isA<StateError>().having(
            (e) => e.toString(),
            'message',
            contains('was not JPEG'),
          ),
        ),
      );
      service.dispose();
    });

    test('fetchPreviewJpeg posts download=1 and returns bytes', () async {
      final jpeg = <int>[0xff, 0xd8, 0xff, 0xd9, ...List.filled(40, 2)];
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/camera/preview');
        expect(request.url.queryParameters['download'], '1');
        return http.Response.bytes(jpeg, 200);
      });
      final service = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: true,
          baseUrl: 'http://192.168.2.50:8791',
          livePreviewEnabled: true,
        ),
        client: client,
      );
      expect(service.shouldShowLivePreview, isTrue);
      expect(service.livePreviewUrl, 'http://192.168.2.50:8791/camera/live');
      expect(
        service.previewFrameUrl,
        'http://192.168.2.50:8791/camera/preview?download=1',
      );
      final bytes = await service.fetchPreviewJpeg();
      expect(bytes.length, jpeg.length);
      service.dispose();
    });

    test('fetchPreviewJpeg throws when not configured', () async {
      final service = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: false,
          baseUrl: 'http://192.168.2.50:8791',
        ),
      );
      await expectLater(service.fetchPreviewJpeg(), throwsStateError);
      service.dispose();
    });

    test('ensureLiveView posts /camera/live-view and parses flags', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/camera/live-view');
        return http.Response(
          jsonEncode({
            'ok': true,
            'enabled': true,
            'woke': true,
            'holding': true,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = LocalCameraService(config: config, client: client);
      final result = await service.ensureLiveView();
      expect(result.enabled, isTrue);
      expect(result.woke, isTrue);
      expect(result.holding, isTrue);
      service.dispose();
    });

    test('ensureLiveView accepts holding when enabled is false', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'ok': true,
            'enabled': false,
            'woke': true,
            'holding': true,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = LocalCameraService(config: config, client: client);
      final result = await service.ensureLiveView();
      expect(result.enabled, isFalse);
      expect(result.holding, isTrue);
      service.dispose();
    });

    test('ensureLiveView throws when sidecar returns error status', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'ok': false, 'error': 'NO_CAMERA'}),
          404,
        );
      });
      final service = LocalCameraService(config: config, client: client);
      await expectLater(service.ensureLiveView(), throwsStateError);
      service.dispose();
    });

    test('ensureLiveView throws when not configured', () async {
      final service = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: false,
          baseUrl: 'http://192.168.2.50:8791',
        ),
      );
      await expectLater(service.ensureLiveView(), throwsStateError);
      service.dispose();
    });

    test('ensureLiveView truncates long error bodies', () async {
      final client = MockClient((request) async {
        return http.Response(
          '{"ok":false,"enabled":false,"holding":false,"error":"${'y' * 300}"}',
          502,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = LocalCameraService(config: config, client: client);
      await expectLater(
        service.ensureLiveView(),
        throwsA(
          isA<StateError>().having(
            (e) => '$e'.length,
            'message length',
            lessThan(400),
          ),
        ),
      );
      service.dispose();
    });

    test('ensureLiveView throws on invalid JSON body', () async {
      final client = MockClient((request) async {
        return http.Response('not-json', 200);
      });
      final service = LocalCameraService(config: config, client: client);
      await expectLater(
        service.ensureLiveView(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('invalid JSON'),
          ),
        ),
      );
      service.dispose();
    });

    test('postClientEvent swallows network errors', () async {
      final client = MockClient((request) async {
        throw Exception('log down');
      });
      final service = LocalCameraService(config: config, client: client);
      await service.postClientEvent('pose_ready');
      service.dispose();
    });

    test('capture throws when sidecar returns JSON error body', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'ok': false, 'error': 'no focus'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = LocalCameraService(config: config, client: client);
      await expectLater(service.capture(), throwsStateError);
      service.dispose();
    });

    test('isHealthy returns false on HTTP error', () async {
      final client = MockClient((request) async {
        return http.Response('bad', 503);
      });
      final service = LocalCameraService(config: config, client: client);
      expect(await service.isHealthy(), isFalse);
      service.dispose();
    });

    test('isHealthy returns false when health request throws', () async {
      final client = MockClient((request) async {
        throw Exception('network down');
      });
      final service = LocalCameraService(config: config, client: client);
      expect(await service.isHealthy(), isFalse);
      service.dispose();
    });

    test('isListening is true on any HTTP response', () async {
      final ok = LocalCameraService(
        config: config,
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(await ok.isListening(), isTrue);
      ok.dispose();
      final errorStatus = LocalCameraService(
        config: config,
        client: MockClient((_) async => http.Response('down', 500)),
      );
      expect(await errorStatus.isListening(), isTrue);
      errorStatus.dispose();
    });

    test('isListening is false when not configured or request throws', () async {
      final disabled = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: false,
          baseUrl: 'http://127.0.0.1:8791',
        ),
      );
      expect(await disabled.isListening(), isFalse);
      disabled.dispose();
      final down = LocalCameraService(
        config: config,
        client: MockClient((_) async => throw Exception('Connection refused')),
      );
      expect(await down.isListening(), isFalse);
      down.dispose();
    });

    test('capture throws when not configured', () async {
      const disabled = CameraSidecarConfig(
        enabled: false,
        baseUrl: 'http://192.168.2.50:8791',
      );
      final service = LocalCameraService(config: disabled);
      await expectLater(service.capture(), throwsStateError);
      service.dispose();
    });

    test('capture throws on HTTP failure and empty body', () async {
      final client = MockClient((request) async {
        return http.Response('server error', 500);
      });
      final service = LocalCameraService(config: config, client: client);
      await expectLater(service.capture(), throwsStateError);
      service.dispose();

      final emptyClient = MockClient((request) async {
        return http.Response.bytes(<int>[], 200);
      });
      final emptyService = LocalCameraService(config: config, client: emptyClient);
      await expectLater(emptyService.capture(), throwsStateError);
      emptyService.dispose();
    });

    test('joins base paths with and without trailing slash', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/booth/health');
        return http.Response(jsonEncode({'ok': true, 'connected': true}), 200);
      });
      final service = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: true,
          baseUrl: 'http://192.168.2.50:8791/booth/',
        ),
        client: client,
      );
      expect(await service.isHealthy(), isTrue);
      service.dispose();
    });

    test('postClientEvent posts JSON breadcrumb and never throws', () async {
      http.Request? seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response('', 204);
      });
      final service = LocalCameraService(config: config, client: client);
      await service.postClientEvent('pose_ready', {'ready': true});
      expect(seen?.url.path, '/camera/client-log');
      expect(seen?.method, 'POST');
      expect(seen?.headers['X-Fotozen-Corr-Id'], isNotEmpty);
      final body = jsonDecode(seen!.body) as Map<String, dynamic>;
      expect(body['type'], 'pose_ready');
      final detail = body['detail'] as Map<String, dynamic>;
      expect(detail['ready'], isTrue);
      expect(detail['corrId'], isNotEmpty);
      service.dispose();
    });

    test('postClientEvent includes sessionId from SessionManager', () async {
      SharedPreferences.setMockInitialValues({});
      SessionManager().clearSession();
      addTearDown(SessionManager().clearSession);
      SessionManager().setSessionFromResponse({
        'id': 'sess-sidecar',
        'sessionId': 'sess-sidecar',
        'termsAccepted': true,
        'termsAcceptedAt': DateTime.now().toIso8601String(),
        'attemptsUsed': 0,
        'generatedImages': <dynamic>[],
        'expiresAt':
            DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
      });
      http.Request? seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response('', 204);
      });
      final service = LocalCameraService(config: config, client: client);
      await service.postClientEvent('pose_ready', {'ready': true});
      final body = jsonDecode(seen!.body) as Map<String, dynamic>;
      final detail = body['detail'] as Map<String, dynamic>;
      expect(detail['sessionId'], 'sess-sidecar');
      service.dispose();
    });

    test('default constructor uses environment sidecar config', () async {
      final service = LocalCameraService(
        client: MockClient((_) async => http.Response('bad', 503)),
      );
      expect(await service.isHealthy(), isFalse);
      service.dispose();
    });

    test('capture truncates long HTTP error bodies', () async {
      final client = MockClient((request) async {
        return http.Response('x' * 300, 500);
      });
      final service = LocalCameraService(config: config, client: client);
      await expectLater(
        service.capture(),
        throwsA(isA<StateError>().having(
          (e) => e.message!.length,
          'message length',
          lessThan(300),
        )),
      );
      service.dispose();
    });
  });
}
