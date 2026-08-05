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
