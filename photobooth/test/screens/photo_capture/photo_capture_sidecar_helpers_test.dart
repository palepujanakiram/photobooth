import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:photobooth/screens/photo_capture/photo_capture_sidecar_helpers.dart';
import 'package:photobooth/services/local_camera_service.dart';
import 'package:photobooth/utils/camera_sidecar_config.dart';
import 'package:photobooth/utils/image_helper.dart';

import '../../helpers/tiny_jpeg.dart';

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

  group('ensureCanonLiveViewForHdmiPose', () {
    test('no-ops when service null or not configured', () async {
      expect(
        await ensureCanonLiveViewForHdmiPose(null),
        (ok: false, holding: false),
      );
      final disabled = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: false,
          baseUrl: 'http://192.168.2.50:8791',
        ),
        client: MockClient((_) async => http.Response('', 500)),
      );
      expect(
        await ensureCanonLiveViewForHdmiPose(disabled),
        (ok: false, holding: false),
      );
      disabled.dispose();
    });

    test('calls ensureLiveView when configured', () async {
      var liveViewHits = 0;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/camera/client-log')) {
          return http.Response('', 204);
        }
        expect(request.url.path, '/camera/live-view');
        liveViewHits++;
        return http.Response(
          '{"ok":true,"enabled":true,"woke":false,"holding":true}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: true,
          baseUrl: 'http://192.168.2.50:8791',
        ),
        client: client,
      );
      final result = await ensureCanonLiveViewForHdmiPose(service);
      expect(result.ok, isTrue);
      expect(result.holding, isTrue);
      expect(liveViewHits, 1);
      service.dispose();
    });

    test('retries until enabled or holding', () async {
      var liveViewHits = 0;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/camera/client-log')) {
          return http.Response('', 204);
        }
        liveViewHits++;
        if (liveViewHits < 2) {
          return http.Response(
            '{"ok":true,"enabled":false,"woke":false,"holding":false}',
            502,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          '{"ok":true,"enabled":false,"woke":false,"holding":true}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: true,
          baseUrl: 'http://192.168.2.50:8791',
        ),
        client: client,
      );
      final result = await ensureCanonLiveViewForHdmiPose(service);
      expect(result.ok, isTrue);
      expect(result.holding, isTrue);
      expect(liveViewHits, 2);
      service.dispose();
    });

    test('swallows ensureLiveView failures', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/camera/client-log')) {
          return http.Response('', 204);
        }
        return http.Response('{"ok":false}', 502);
      });
      final service = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: true,
          baseUrl: 'http://192.168.2.50:8791',
        ),
        client: client,
      );
      final result = await ensureCanonLiveViewForHdmiPose(service);
      expect(result.ok, isFalse);
      expect(result.holding, isFalse);
      service.dispose();
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
        if (request.url.path.endsWith('/camera/client-log')) {
          return http.Response('', 204);
        }
        if (request.url.path.endsWith('/health')) {
          return http.Response('{"ok":true,"connected":true}', 200);
        }
        expect(request.url.queryParameters['resumeLiveView'], '1');
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

    test('passes resumeLiveView=0 for classic 1-shot handoff', () async {
      final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9, ...List.filled(64, 2)]);
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/camera/client-log')) {
          return http.Response('', 204);
        }
        if (request.url.path.endsWith('/health')) {
          return http.Response('{"ok":true,"connected":true}', 200);
        }
        expect(request.url.queryParameters['resumeLiveView'], '0');
        return http.Response.bytes(jpeg, 200);
      });
      final service = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: true,
          baseUrl: 'http://192.168.2.50:8791',
        ),
        client: client,
      );
      final file = await tryCaptureFromSidecar(service, resumeLiveView: false);
      expect(file, isNotNull);
      service.dispose();
    });

    test('attempts capture even when health soft-fails', () async {
      final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9, ...List.filled(64, 2)]);
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/camera/client-log')) {
          return http.Response('', 204);
        }
        if (request.url.path.endsWith('/health')) {
          return http.Response('{"ok":true,"connected":false}', 200);
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
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), jpeg);
      service.dispose();
    });

    test('returns null when capture throws', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/camera/client-log')) {
          return http.Response('', 204);
        }
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
    test('bakes EXIF into photos dir without full normalize', () async {
      final jpeg = kTinyJpegBytes;
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
      final saved = await persistSidecarCaptureStill(raw!);
      expect(saved.path, isNotEmpty);
      expect(
        saved.path.contains('sidecar') || saved.path.contains('photos'),
        isTrue,
      );
      expect(await saved.readAsBytes(), isNotEmpty);
      await ImageHelper.tryDeleteLocalFile(raw.path);
      await ImageHelper.tryDeleteLocalFile(saved.path);
      service.dispose();
    });

    test('writes empty-path XFile then bakes to photos dir', () async {
      final jpeg = kTinyJpegBytes;
      final raw = XFile.fromData(
        jpeg,
        mimeType: 'image/jpeg',
        name: 'memory.jpg',
      );
      expect(raw.path, isEmpty);
      final saved = await persistSidecarCaptureStill(raw);
      expect(saved.path, isNotEmpty);
      expect(
        saved.path.contains('sidecar') || saved.path.contains('photos'),
        isTrue,
      );
      expect(await saved.readAsBytes(), isNotEmpty);
      await ImageHelper.tryDeleteLocalFile(saved.path);
    });

    test('applies bakeQuarterTurns clockwise', () async {
      final landscape = img.Image(width: 40, height: 20);
      img.fill(landscape, color: img.ColorRgb8(10, 10, 10));
      for (var y = 0; y < 20; y++) {
        for (var x = 0; x < 8; x++) {
          landscape.setPixelRgb(x, y, 255, 0, 0);
        }
      }
      final jpeg = Uint8List.fromList(img.encodeJpg(landscape, quality: 90));
      final raw = XFile.fromData(jpeg, mimeType: 'image/jpeg', name: 'l.jpg');
      final saved = await persistSidecarCaptureStill(
        raw,
        bakeQuarterTurns: 1,
      );
      final baked = img.decodeImage(await saved.readAsBytes());
      expect(baked, isNotNull);
      // 90° CW: 40×20 → 20×40
      expect(baked!.width, 20);
      expect(baked.height, 40);
      await ImageHelper.tryDeleteLocalFile(saved.path);
    });
  });
}
