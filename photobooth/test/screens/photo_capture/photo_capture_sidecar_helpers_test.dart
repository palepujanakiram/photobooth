import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_sidecar_helpers.dart';
import 'package:photobooth/services/local_camera_service.dart';
import 'package:photobooth/utils/camera_sidecar_config.dart';
import 'package:photobooth/utils/image_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getTemporaryDirectory' ||
            call.method == 'getApplicationSupportDirectory') {
          return '/tmp';
        }
        return null;
      },
    );
  });

  group('isSidecarCameraId', () {
    test('matches sidecar prefix', () {
      expect(isSidecarCameraId('sidecar:FZ200D'), isTrue);
      expect(isSidecarCameraId('uvc:1:2:cam'), isFalse);
      expect(isSidecarCameraId(null), isFalse);
      expect(isSidecarCameraId(''), isFalse);
    });
  });

  group('tryCaptureFromSidecar', () {
    test('returns null when service null or not configured', () async {
      expect(await tryCaptureFromSidecar(null), isNull);
      final disabled = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: false,
          baseUrl: 'http://192.168.2.50:8791',
        ),
        client: MockClient((_) async => http.Response('', 500)),
      );
      expect(await tryCaptureFromSidecar(disabled), isNull);
      disabled.dispose();
    });

    test('returns path-backed XFile when healthy and capture succeeds', () async {
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
        ),
        client: client,
      );
      final file = await tryCaptureFromSidecar(service);
      expect(file, isA<XFile>());
      expect(file!.path, isNotEmpty);
      expect(await file.readAsBytes(), jpeg);
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
        ),
        client: client,
      );
      expect(await tryCaptureFromSidecar(service), isNull);
      service.dispose();
    });
  });

  group('persistSidecarCaptureStill', () {
    test('falls back to copy when normalize times out', () async {
      final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9, ...List.filled(32, 7)]);
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
        ),
        client: client,
      );
      final raw = await tryCaptureFromSidecar(service);
      expect(raw, isNotNull);
      final saved = await persistSidecarCaptureStill(
        raw!,
        normalizeTimeout: Duration.zero,
      );
      expect(saved.path, isNotEmpty);
      expect(await saved.readAsBytes(), jpeg);
      expect(saved.path.contains('photos'), isTrue);
      await ImageHelper.tryDeleteLocalFile(raw.path);
      await ImageHelper.tryDeleteLocalFile(saved.path);
      service.dispose();
    });
  });
}
