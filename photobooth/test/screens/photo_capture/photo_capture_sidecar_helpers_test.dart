import 'dart:async';
import 'dart:io';
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

http.Response? sidecarBoothMetaResponse(http.Request request) {
  final path = request.url.path;
  if (path.endsWith('/camera/client-log')) {
    return http.Response('', 204);
  }
  if (path.endsWith('/health')) {
    return http.Response('{"ok":true,"connected":true}', 200);
  }
  if (path.endsWith('/camera/prepare-still')) {
    return http.Response('', 200);
  }
  if (path.endsWith('/camera/preview')) {
    return http.Response.bytes(kTinyJpegBytes, 200);
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String tempDirPath = '/tmp';

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getTemporaryDirectory' ||
            call.method == 'getApplicationSupportDirectory') {
          return tempDirPath;
        }
        return null;
      },
    );
  });

  tearDown(() {
    debugSidecarHelpersForceWeb = false;
    tempDirPath = '/tmp';
  });

  group('isSidecarCameraId', () {
    test('matches sidecar prefix', () {
      expect(isSidecarCameraId('sidecar:FZ200D'), isTrue);
      expect(isSidecarCameraId('uvc:1:2:cam'), isFalse);
      expect(isSidecarCameraId(null), isFalse);
      expect(isSidecarCameraId(''), isFalse);
    });
  });

  group('shouldTreatSidecarNativeStateAsDead', () {
    test('flags ABI and max_restarts only — crashed is transient', () {
      expect(shouldTreatSidecarNativeStateAsDead('unsupported_abi'), isTrue);
      expect(shouldTreatSidecarNativeStateAsDead('max_restarts'), isTrue);
      expect(shouldTreatSidecarNativeStateAsDead('crashed'), isFalse);
      expect(shouldTreatSidecarNativeStateAsDead('running'), isFalse);
      expect(shouldTreatSidecarNativeStateAsDead('waiting_usb'), isFalse);
      expect(shouldTreatSidecarNativeStateAsDead('restarting'), isFalse);
      expect(shouldTreatSidecarNativeStateAsDead('idle'), isFalse);
      expect(shouldTreatSidecarNativeStateAsDead(''), isFalse);
    });
  });

  group('sidecarNativeProcessCanServeHttp', () {
    LocalCameraService configuredService() {
      return LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: true,
          baseUrl: 'http://127.0.0.1:8791',
          livePreviewEnabled: true,
        ),
        client: MockClient((_) async => http.Response('{}', 200)),
      );
    }

    test('false when service is null or not configured', () async {
      expect(
        await sidecarNativeProcessCanServeHttp(
          null,
          queryNativeState: () async => 'running',
        ),
        isFalse,
      );
      final disabled = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: false,
          baseUrl: 'http://127.0.0.1:8791',
        ),
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(
        await sidecarNativeProcessCanServeHttp(
          disabled,
          queryNativeState: () async => 'running',
        ),
        isFalse,
      );
      disabled.dispose();
    });

    test('true when native process is running', () async {
      final service = configuredService();
      expect(
        await sidecarNativeProcessCanServeHttp(
          service,
          queryNativeState: () async => 'running',
        ),
        isTrue,
      );
      expect(service.isConfigured, isTrue);
      service.dispose();
    });

    test('true when idle but HTTP is listening', () async {
      final service = configuredService();
      expect(
        await sidecarNativeProcessCanServeHttp(
          service,
          queryNativeState: () async => 'idle',
        ),
        isTrue,
      );
      expect(service.isConfigured, isTrue);
      service.dispose();
    });

    test('idle and HTTP down leaves config intact for warm-up retry', () async {
      final service = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: true,
          baseUrl: 'http://127.0.0.1:8791',
          livePreviewEnabled: true,
          connectionMode: CameraConnectionMode.direct,
        ),
        client: MockClient((_) async => throw Exception('Connection refused')),
      );
      expect(
        await sidecarNativeProcessCanServeHttp(
          service,
          queryNativeState: () async => 'idle',
        ),
        isFalse,
      );
      // Must remain configured so pose can retry after asset extract / bind.
      expect(service.isConfigured, isTrue);
      service.dispose();
    });

    test('marks unavailable on unsupported_abi', () async {
      final service = configuredService();
      expect(
        await sidecarNativeProcessCanServeHttp(
          service,
          queryNativeState: () async => 'unsupported_abi',
        ),
        isFalse,
      );
      expect(service.isConfigured, isFalse);
      expect(service.shouldShowLivePreview, isFalse);
      service.setForceLivePreview(true);
      expect(service.shouldShowLivePreview, isFalse);
      service.dispose();
    });

    test('does not poison on transient crashed; poisons on max_restarts', () async {
      // HTTP still up during a brief native restart gap → keep serving.
      final crashed = configuredService();
      expect(
        await sidecarNativeProcessCanServeHttp(
          crashed,
          queryNativeState: () async => 'crashed',
        ),
        isTrue,
      );
      expect(crashed.isConfigured, isTrue);
      crashed.dispose();

      final crashedDown = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: true,
          baseUrl: 'http://127.0.0.1:8791',
          livePreviewEnabled: true,
          connectionMode: CameraConnectionMode.direct,
        ),
        client: MockClient((_) async => throw Exception('Connection refused')),
      );
      expect(
        await sidecarNativeProcessCanServeHttp(
          crashedDown,
          queryNativeState: () async => 'crashed',
        ),
        isFalse,
      );
      expect(crashedDown.isConfigured, isTrue);
      crashedDown.dispose();

      final maxed = configuredService();
      expect(
        await sidecarNativeProcessCanServeHttp(
          maxed,
          queryNativeState: () async => 'max_restarts',
        ),
        isFalse,
      );
      expect(maxed.isConfigured, isFalse);
      maxed.dispose();
    });

    test('clears prior poison when native state recovers to running', () async {
      final service = configuredService();
      service.markRuntimeUnavailable();
      expect(service.isConfigured, isFalse);
      expect(service.hasSidecarEndpoint, isTrue);
      expect(
        await sidecarNativeProcessCanServeHttp(
          service,
          queryNativeState: () async => 'running',
        ),
        isTrue,
      );
      expect(service.isConfigured, isTrue);
      service.dispose();
    });

    test('Pi/LAN ignores native crash — does not poison remote config', () async {
      final service = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: true,
          baseUrl: 'http://192.168.1.50:8791',
          livePreviewEnabled: true,
          connectionMode: CameraConnectionMode.pi,
        ),
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(
        await sidecarNativeProcessCanServeHttp(
          service,
          queryNativeState: () async => 'crashed',
        ),
        isTrue,
      );
      expect(service.isConfigured, isTrue);
      service.dispose();
    });

    test('query errors keep sidecar only when HTTP is listening', () async {
      final up = configuredService();
      expect(
        await sidecarNativeProcessCanServeHttp(
          up,
          queryNativeState: () => throw Exception('channel down'),
        ),
        isTrue,
      );
      up.dispose();
      final down = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: true,
          baseUrl: 'http://127.0.0.1:8791',
          livePreviewEnabled: true,
          connectionMode: CameraConnectionMode.direct,
        ),
        client: MockClient((_) async => throw Exception('Connection refused')),
      );
      expect(
        await sidecarNativeProcessCanServeHttp(
          down,
          queryNativeState: () => Completer<String>().future,
          nativeStateTimeout: Duration.zero,
        ),
        isFalse,
      );
      // Timeout → idle; HTTP down is warm-up, not terminal poison.
      expect(down.isConfigured, isTrue);
      down.dispose();
    });
  });

  group('shouldPreferSidecarLivePreviewFrameForCapture', () {
    test('false when sidecar EVF is the pose preview', () {
      expect(
        shouldPreferSidecarLivePreviewFrameForCapture(
          sidecarIsPosePreview: true,
        ),
        isFalse,
      );
    });

    test('true when HDMI/UVC is preview and sidecar only captures', () {
      expect(
        shouldPreferSidecarLivePreviewFrameForCapture(
          sidecarIsPosePreview: false,
        ),
        isTrue,
      );
    });
  });

  group('waitForDirectSidecarPoseReady', () {
    test('returns true when sidecar becomes ready during poll', () async {
      var calls = 0;
      final ready = await waitForDirectSidecarPoseReady(
        canServePosePreview: () async {
          calls++;
          return calls >= 3;
        },
        timeout: const Duration(seconds: 2),
        pollInterval: const Duration(milliseconds: 10),
      );
      expect(ready, isTrue);
      expect(calls, 3);
    });

    test('returns false when sidecar never becomes ready', () async {
      final ready = await waitForDirectSidecarPoseReady(
        canServePosePreview: () async => false,
        timeout: const Duration(milliseconds: 50),
        pollInterval: const Duration(milliseconds: 10),
      );
      expect(ready, isFalse);
    });
  });

  group('nativeEdsdkSidecarIsRunning', () {
    test('true only for running', () async {
      expect(
        await nativeEdsdkSidecarIsRunning(() async => 'running'),
        isTrue,
      );
      expect(
        await nativeEdsdkSidecarIsRunning(() async => 'idle'),
        isFalse,
      );
      expect(
        await nativeEdsdkSidecarIsRunning(() async => 'crashed'),
        isFalse,
      );
    });

    test('false on timeout or throw', () async {
      expect(
        await nativeEdsdkSidecarIsRunning(
          () => Completer<String>().future,
          nativeStateTimeout: Duration.zero,
        ),
        isFalse,
      );
      expect(
        await nativeEdsdkSidecarIsRunning(() => throw Exception('channel')),
        isFalse,
      );
    });
  });

  group('shouldRefuseCameraxFallbackWhenSidecarMisses', () {
    test('refuses CameraX when Pi stills are configured', () {
      expect(
        shouldRefuseCameraxFallbackWhenSidecarMisses(sidecarConfigured: true),
        isTrue,
      );
      expect(
        shouldRefuseCameraxFallbackWhenSidecarMisses(sidecarConfigured: false),
        isFalse,
      );
    });

    test('allows CameraX when device camera preview is active', () {
      expect(
        shouldRefuseCameraxFallbackWhenSidecarMisses(
          sidecarConfigured: true,
          deviceCameraCaptureActive: true,
        ),
        isFalse,
      );
    });
  });

  group('shouldSkipSidecarStillForDeviceCamera', () {
    test('skips when preferDeviceCameraCapture is set', () {
      expect(
        shouldSkipSidecarStillForDeviceCamera(
          preferDeviceCameraCapture: true,
          cameraXInitialized: false,
          usesSidecarLivePreview: false,
        ),
        isTrue,
      );
    });

    test('skips when CameraX is live and sidecar is not the pose preview', () {
      expect(
        shouldSkipSidecarStillForDeviceCamera(
          preferDeviceCameraCapture: false,
          cameraXInitialized: true,
          usesSidecarLivePreview: false,
        ),
        isTrue,
      );
    });

    test('skips when CameraX is live even if sidecar EVF flag is on', () {
      expect(
        shouldSkipSidecarStillForDeviceCamera(
          preferDeviceCameraCapture: false,
          cameraXInitialized: true,
          usesSidecarLivePreview: true,
        ),
        isTrue,
      );
    });

    test('keeps sidecar stills for EVF / HDMI Pi booths', () {
      expect(
        shouldSkipSidecarStillForDeviceCamera(
          preferDeviceCameraCapture: false,
          cameraXInitialized: false,
          usesSidecarLivePreview: true,
        ),
        isFalse,
      );
      expect(
        shouldSkipSidecarStillForDeviceCamera(
          preferDeviceCameraCapture: false,
          cameraXInitialized: false,
          usesSidecarLivePreview: false,
        ),
        isFalse,
      );
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

  group('shouldPreferLiveViewJpeg', () {
    test('keeps still when luma is missing or still is bright enough', () {
      expect(
        shouldPreferLiveViewJpeg(stillLuma: null, liveLuma: 120),
        isFalse,
      );
      expect(
        shouldPreferLiveViewJpeg(stillLuma: 20, liveLuma: null),
        isFalse,
      );
      expect(
        shouldPreferLiveViewJpeg(stillLuma: 80, liveLuma: 140),
        isFalse,
      );
      expect(
        shouldPreferLiveViewJpeg(stillLuma: 20, liveLuma: 30),
        isFalse,
      );
    });

    test('prefers live when still is almost black and live is brighter', () {
      expect(
        shouldPreferLiveViewJpeg(stillLuma: 18, liveLuma: 110),
        isTrue,
      );
    });
  });

  group('pickSidecarCaptureJpeg', () {
    test('returns still when live is missing or not jpeg', () async {
      final still = Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]);
      expect(
        await pickSidecarCaptureJpeg(stillJpeg: still, liveJpeg: null),
        still,
      );
      expect(
        await pickSidecarCaptureJpeg(
          stillJpeg: still,
          liveJpeg: Uint8List.fromList([0x00, 0x01]),
        ),
        still,
      );
    });

    test('returns live jpeg when still luma is too dark', () async {
      final still = Uint8List.fromList([0xff, 0xd8, 0xff, 0x01]);
      final live = Uint8List.fromList([0xff, 0xd8, 0xff, 0x02]);
      final picked = await pickSidecarCaptureJpeg(
        stillJpeg: still,
        liveJpeg: live,
        meanLuma: (bytes) async => bytes[3] == 0x01 ? 12 : 120,
      );
      expect(picked, live);
    });

    test('keeps still when live is not brighter enough', () async {
      final still = Uint8List.fromList([0xff, 0xd8, 0xff, 0x01]);
      final live = Uint8List.fromList([0xff, 0xd8, 0xff, 0x02]);
      final picked = await pickSidecarCaptureJpeg(
        stillJpeg: still,
        liveJpeg: live,
        meanLuma: (bytes) async => 90,
      );
      expect(picked, still);
    });
  });

  group('sidecarLiveJpegCanBePoseCapture', () {
    test('accepts jpeg bytes and rejects empty or non-jpeg', () {
      expect(
        sidecarLiveJpegCanBePoseCapture(
          Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]),
        ),
        isTrue,
      );
      expect(sidecarLiveJpegCanBePoseCapture(null), isFalse);
      expect(sidecarLiveJpegCanBePoseCapture(Uint8List(0)), isFalse);
      expect(
        sidecarLiveJpegCanBePoseCapture(Uint8List.fromList([0x00, 0x01])),
        isFalse,
      );
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
        final meta = sidecarBoothMetaResponse(request);
        if (meta != null) return meta;
        expect(request.url.path, endsWith('/camera/capture'));
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

    test('calls prepare-still before capture', () async {
      final jpeg =
          Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9, ...List.filled(64, 2)]);
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        final meta = sidecarBoothMetaResponse(request);
        if (meta != null) return meta;
        return http.Response.bytes(jpeg, 200);
      });
      final service = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: true,
          baseUrl: 'http://192.168.2.50:8791',
        ),
        client: client,
      );
      expect(await tryCaptureFromSidecar(service), isNotNull);
      expect(paths, contains('/camera/prepare-still'));
      expect(
        paths.indexOf('/camera/prepare-still'),
        lessThan(
          paths.indexWhere((p) => p.endsWith('/camera/capture')),
        ),
      );
      service.dispose();
    });

    test('preferLivePreviewFrame uses EVF jpeg and skips mechanical shutter',
        () async {
      final still =
          Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9, ...List.filled(64, 9)]);
      final paths = <String>[];
      var usedLive = false;
      final client = MockClient((request) async {
        paths.add(request.url.path);
        final meta = sidecarBoothMetaResponse(request);
        if (meta != null) return meta;
        return http.Response.bytes(still, 200);
      });
      final service = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: true,
          baseUrl: 'http://192.168.2.50:8791',
          livePreviewEnabled: true,
        ),
        client: client,
      );
      final file = await tryCaptureFromSidecar(
        service,
        preferLivePreviewFrame: true,
        onUsedLivePreviewFrame: () => usedLive = true,
      );
      expect(usedLive, isTrue);
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), kTinyJpegBytes);
      expect(paths.where((p) => p.endsWith('/camera/capture')), isEmpty);
      expect(paths.where((p) => p.endsWith('/camera/prepare-still')), isEmpty);
      service.dispose();
    });

    test('passes resumeLiveView=0 for classic 1-shot handoff', () async {
      final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9, ...List.filled(64, 2)]);
      final client = MockClient((request) async {
        final meta = sidecarBoothMetaResponse(request);
        if (meta != null) return meta;
        expect(request.url.path, endsWith('/camera/capture'));
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

    test('requests strip print long-edge and quality when preferred', () async {
      final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9, ...List.filled(64, 2)]);
      final client = MockClient((request) async {
        final meta = sidecarBoothMetaResponse(request);
        if (meta != null) return meta;
        expect(request.url.path, endsWith('/camera/capture'));
        expect(request.url.queryParameters['maxLongEdge'], '1920');
        expect(request.url.queryParameters['jpegQuality'], '92');
        return http.Response.bytes(jpeg, 200);
      });
      final service = LocalCameraService(
        config: const CameraSidecarConfig(
          enabled: true,
          baseUrl: 'http://192.168.2.50:8791',
        ),
        client: client,
      );
      final file = await tryCaptureFromSidecar(
        service,
        preferStripPrintQuality: true,
      );
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

    test('returns null when capture bytes are empty', () async {
      final service = _EmptyBytesCameraService();
      expect(await tryCaptureFromSidecar(service), isNull);
      service.dispose();
    });

    test('returns in-memory XFile on web path', () async {
      debugSidecarHelpersForceWeb = true;
      final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9, ...List.filled(32, 3)]);
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/camera/client-log')) {
          return http.Response('', 204);
        }
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
      expect(file, isNotNull);
      expect(file!.path, isEmpty);
      expect(await file.readAsBytes(), jpeg);
      service.dispose();
    });

    test('falls back to memory when temp write fails', () async {
      final blocker = File(
        '${Directory.systemTemp.path}/sidecar_temp_blocker_'
        '${DateTime.now().microsecondsSinceEpoch}',
      );
      await blocker.writeAsBytes(const [1]);
      tempDirPath = blocker.path;
      addTearDown(() {
        if (blocker.existsSync()) blocker.deleteSync();
      });

      final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9, ...List.filled(32, 4)]);
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/camera/client-log')) {
          return http.Response('', 204);
        }
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
      expect(file, isNotNull);
      expect(file!.path, isEmpty);
      expect(await file.readAsBytes(), jpeg);
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

    test('returns raw file unchanged on web path', () async {
      debugSidecarHelpersForceWeb = true;
      final raw = XFile.fromData(
        kTinyJpegBytes,
        mimeType: 'image/jpeg',
        name: 'web.jpg',
      );
      final saved = await persistSidecarCaptureStill(raw);
      expect(identical(saved, raw), isTrue);
    });

    test('throws when empty-path capture has no bytes', () async {
      final raw = XFile.fromData(
        Uint8List(0),
        mimeType: 'image/jpeg',
        name: 'empty.jpg',
      );
      await expectLater(
        persistSidecarCaptureStill(raw),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Sidecar capture is empty'),
          ),
        ),
      );
    });

    test('throws when capture bytes are not JPEG', () async {
      final raw = XFile.fromData(
        Uint8List.fromList([0x49, 0x49, 0x2a, 0x00, ...List.filled(24, 0)]),
        mimeType: 'image/jpeg',
        name: 'raw.cr2',
      );
      await expectLater(
        persistSidecarCaptureStill(raw),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('not a JPEG still'),
          ),
        ),
      );
    });
  });
}

class _EmptyBytesCameraService extends LocalCameraService {
  _EmptyBytesCameraService()
      : super(
          config: const CameraSidecarConfig(
            enabled: true,
            baseUrl: 'http://192.168.2.50:8791',
          ),
          client: MockClient((_) async => http.Response('', 204)),
        );

  @override
  Future<bool> isHealthy({String? corrId}) async => true;

  @override
  Future<Uint8List> capture({
    int maxLongEdge = kSidecarCaptureMaxLongEdge,
    int jpegQuality = kSidecarCaptureJpegQuality,
    bool resumeLiveView = true,
    String? corrId,
  }) async {
    return Uint8List(0);
  }
}
