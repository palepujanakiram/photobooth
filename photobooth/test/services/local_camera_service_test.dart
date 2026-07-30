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
          token: 'x',
        ).isConfigured,
        isTrue,
      );
      expect(
        const CameraSidecarConfig(
          enabled: false,
          baseUrl: 'http://192.168.2.50:8791',
          token: 'x',
        ).isConfigured,
        isFalse,
      );
    });
  });

  group('LocalCameraService', () {
    const config = CameraSidecarConfig(
      enabled: true,
      baseUrl: 'http://192.168.2.50:8791',
      token: 'change-me',
    );

    test('isHealthy true when connected', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/health');
        expect(request.headers['X-Camera-Token'], 'change-me');
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
        expect(request.headers['X-Camera-Token'], 'change-me');
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
  });
}
