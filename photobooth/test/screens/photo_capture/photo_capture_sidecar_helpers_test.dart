import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_sidecar_helpers.dart';
import 'package:photobooth/services/local_camera_service.dart';
import 'package:photobooth/utils/camera_sidecar_config.dart';

void main() {
  group('tryCaptureFromSidecar', () {
    test('returns null when service null or not configured', () async {
      expect(await tryCaptureFromSidecar(null), isNull);
      final disabled = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: false,
          baseUrl: 'http://192.168.2.50:8791',
          token: '',
        ),
        client: MockClient((_) async => http.Response('', 500)),
      );
      expect(await tryCaptureFromSidecar(disabled), isNull);
      disabled.dispose();
    });

    test('returns XFile when healthy and capture succeeds', () async {
      final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9, ...List.filled(64, 2)]);
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/health')) {
          return http.Response('{"ok":true,"connected":true}', 200);
        }
        return http.Response.bytes(jpeg, 200);
      });
      final service = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: true,
          baseUrl: 'http://192.168.2.50:8791',
          token: 't',
        ),
        client: client,
      );
      final file = await tryCaptureFromSidecar(service);
      expect(file, isA<XFile>());
      expect(await file!.readAsBytes(), jpeg);
      expect(file.mimeType, 'image/jpeg');
      service.dispose();
    });

    test('returns null when unhealthy', () async {
      final client = MockClient((request) async {
        return http.Response('{"ok":true,"connected":false}', 200);
      });
      final service = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: true,
          baseUrl: 'http://192.168.2.50:8791',
          token: 't',
        ),
        client: client,
      );
      expect(await tryCaptureFromSidecar(service), isNull);
      service.dispose();
    });
    test('returns null when capture throws', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/health')) {
          return http.Response('{"ok":true,"connected":true}', 200);
        }
        throw Exception('capture failed');
      });
      final service = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: true,
          baseUrl: 'http://192.168.2.50:8791',
          token: 't',
        ),
        client: client,
      );
      expect(await tryCaptureFromSidecar(service), isNull);
      service.dispose();
    });
  });
}
