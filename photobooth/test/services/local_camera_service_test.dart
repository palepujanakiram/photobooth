import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photobooth/services/local_camera_service.dart';
import 'package:photobooth/utils/camera_sidecar_config.dart';

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
      final body = jsonDecode(seen!.body) as Map<String, dynamic>;
      expect(body['type'], 'pose_ready');
      expect(body['detail'], {'ready': true});
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
