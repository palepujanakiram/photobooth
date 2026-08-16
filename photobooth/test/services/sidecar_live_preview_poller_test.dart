import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photobooth/services/local_camera_service.dart';
import 'package:photobooth/services/sidecar_live_preview_poller.dart';
import 'package:photobooth/utils/camera_sidecar_config.dart';

void main() {
  group('SidecarLivePreviewPoller', () {
    test('emits frames while running and stops after dispose', () async {
      final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9, ...List.filled(32, 3)]);
      var posts = 0;
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/camera/preview');
        expect(request.url.queryParameters['download'], '1');
        posts++;
        return http.Response.bytes(jpeg, 200);
      });
      final service = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: true,
          baseUrl: 'http://172.16.4.128:8791',
          livePreviewEnabled: true,
        ),
        client: client,
      );
      final frames = <Uint8List>[];
      final poller = SidecarLivePreviewPoller(
        service: service,
        interval: const Duration(milliseconds: 30),
        onFrame: frames.add,
      );
      expect(poller.isRunning, isFalse);
      poller.start();
      expect(poller.isRunning, isTrue);
      poller.start(); // idempotent
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(frames, isNotEmpty);
      expect(posts, greaterThan(0));
      poller.pause();
      final afterPause = posts;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(posts, afterPause);
      poller.resume();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(posts, greaterThan(afterPause));
      poller.dispose();
      final afterDispose = posts;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(posts, afterDispose);
      service.dispose();
    });

    test('isSidecarPreviewWarmingError detects EVF warmup 503s', () {
      expect(
        isSidecarPreviewWarmingError(
          StateError('Camera sidecar preview failed (503): {"error":"no frame"}'),
        ),
        isTrue,
      );
      expect(isSidecarPreviewWarmingError(StateError('connection refused')), isFalse);
    });

    test('reports errors from failed preview fetches', () async {
      final client = MockClient((request) async {
        return http.Response('busy', 503);
      });
      final service = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: true,
          baseUrl: 'http://172.16.4.128:8791',
          livePreviewEnabled: true,
        ),
        client: client,
      );
      final errors = <Object>[];
      final poller = SidecarLivePreviewPoller(
        service: service,
        interval: const Duration(milliseconds: 20),
        onError: errors.add,
      );
      poller.start();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(errors, isNotEmpty);
      poller.dispose();
      service.dispose();
    });

    test('skips when live preview not enabled', () async {
      var posts = 0;
      final client = MockClient((request) async {
        posts++;
        return http.Response.bytes([0xff, 0xd8], 200);
      });
      final service = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: true,
          baseUrl: 'http://172.16.4.128:8791',
        ),
        client: client,
      );
      final poller = SidecarLivePreviewPoller(
        service: service,
        interval: const Duration(milliseconds: 20),
      );
      poller.start();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(posts, 0);
      poller.dispose();
      service.dispose();
    });
  });
}
