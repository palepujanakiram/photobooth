import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/services/direct_ptp_camera_service.dart';
import 'package:photobooth/utils/camera_sidecar_config.dart';
import 'package:photobooth/utils/canon_sidecar_status_channel.dart';
import 'package:photobooth/utils/canon_usb_permission.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.srisarani.fotozenai/canon_sidecar_status');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('isDirectCanonSidecarBooth', () {
    test('true for direct localhost sidecar', () {
      expect(
        isDirectCanonSidecarBooth(
          AppSettingsModel(cameraConnectionMode: 'direct'),
        ),
        isTrue,
      );
    });

    test('false for Pi sidecar host', () {
      expect(
        isDirectCanonSidecarBooth(
          AppSettingsModel(
            cameraConnectionMode: 'pi',
            cameraEnabled: true,
            cameraSidecarHost: '192.168.1.10',
          ),
        ),
        isFalse,
      );
    });
  });

  group('CanonSidecarStatusChannel USB permission', () {
    test('hasUsbPermission and requestUsbPermission forward to native', () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'hasUsbPermission') return false;
        if (call.method == 'requestUsbPermission') return true;
        return null;
      });

      expect(await CanonSidecarStatusChannel.hasUsbPermission(), isFalse);
      expect(await CanonSidecarStatusChannel.requestUsbPermissionIfNeeded(), isTrue);
      expect(calls, ['hasUsbPermission', 'requestUsbPermission']);
    });

    test('canonSidecarAwaitingUsbPermission reads waiting_usb state', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getState') return 'waiting_usb';
        return null;
      });
      expect(await canonSidecarAwaitingUsbPermission(), isTrue);
    });
  });

  group('ensureCanonUsbPermissionForDirectSidecar', () {
    test('returns true when Pi sidecar is configured (no on-device USB)', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final ok = await ensureCanonUsbPermissionForDirectSidecar(
        settings: AppSettingsModel(
          cameraConnectionMode: 'pi',
          cameraEnabled: true,
          cameraSidecarHost: '192.168.1.10',
        ),
      );
      expect(ok, isTrue);
    });

    test('requests USB permission for direct EDSDK sidecar', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var requested = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'isCameraPresent') return true;
        if (call.method == 'hasUsbPermission') return false;
        if (call.method == 'requestUsbPermission') {
          requested = true;
          return true;
        }
        return null;
      });

      final ok = await ensureCanonUsbPermissionForDirectSidecar(
        config: const CameraSidecarConfig(
          enabled: true,
          baseUrl: 'http://127.0.0.1:8791',
          livePreviewEnabled: true,
          connectionMode: CameraConnectionMode.direct,
        ),
      );
      expect(ok, isTrue);
      expect(requested, isTrue);
    });

    test('skips USB request when no Canon body is attached', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var requested = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'isCameraPresent') return false;
        if (call.method == 'requestUsbPermission') {
          requested = true;
          return false;
        }
        return null;
      });

      final ok = await ensureCanonUsbPermissionForDirectSidecar(
        config: const CameraSidecarConfig(
          enabled: true,
          baseUrl: 'http://127.0.0.1:8791',
          livePreviewEnabled: true,
          connectionMode: CameraConnectionMode.direct,
        ),
      );
      expect(ok, isTrue);
      expect(requested, isFalse);
    });
  });

  test('primeCanonUsbOnTermsLaunch no-ops for Pi booths', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final ok = await primeCanonUsbOnTermsLaunch(
      settings: AppSettingsModel(
        cameraConnectionMode: 'pi',
        cameraEnabled: true,
        cameraSidecarHost: '10.0.0.5',
      ),
    );
    expect(ok, isTrue);
  });

  test('warmDirectSidecarAfterUsbGrant tolerates native state query timeout', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'isCameraPresent') return true;
      if (call.method == 'getState') {
        await Future<void>.delayed(const Duration(seconds: 2));
        return 'running';
      }
      return null;
    });
    final client = MockClient((_) async => throw Exception('connection refused'));
    final ok = await warmDirectSidecarAfterUsbGrant(
      config: const CameraSidecarConfig(
        enabled: true,
        baseUrl: 'http://127.0.0.1:8791',
        livePreviewEnabled: true,
        connectionMode: CameraConnectionMode.direct,
      ),
      timeout: const Duration(milliseconds: 50),
      pollInterval: const Duration(milliseconds: 5),
      client: client,
    );
    expect(ok, isFalse);
  });

  test('warmDirectSidecarAfterUsbGrant re-requests USB when waiting_usb', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    var usbRequests = 0;
    var healthCalls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'isCameraPresent') return true;
      if (call.method == 'getState') return 'waiting_usb';
      if (call.method == 'requestUsbPermission') {
        usbRequests++;
        return true;
      }
      return null;
    });
    final client = MockClient((request) async {
      healthCalls++;
      if (healthCalls == 1) throw Exception('connection refused');
      return http.Response(
        '{"ok":true,"connected":true,"backend":"edsdk"}',
        200,
      );
    });
    final ok = await warmDirectSidecarAfterUsbGrant(
      config: const CameraSidecarConfig(
        enabled: true,
        baseUrl: 'http://127.0.0.1:8791',
        livePreviewEnabled: true,
        connectionMode: CameraConnectionMode.direct,
      ),
      pollInterval: const Duration(milliseconds: 5),
      client: client,
    );
    expect(ok, isTrue);
    expect(usbRequests, greaterThan(0));
  });

  test('warmDirectSidecarAfterUsbGrant returns true when health succeeds', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'isCameraPresent') return true;
      if (call.method == 'getState') return 'running';
      return null;
    });
    final client = MockClient((request) async {
      expect(request.url.path, '/health');
      return http.Response(
        '{"ok":true,"connected":true,"backend":"edsdk"}',
        200,
      );
    });
    final ok = await warmDirectSidecarAfterUsbGrant(
      config: const CameraSidecarConfig(
        enabled: true,
        baseUrl: 'http://127.0.0.1:8791',
        livePreviewEnabled: true,
        connectionMode: CameraConnectionMode.direct,
      ),
      client: client,
    );
    expect(ok, isTrue);
  });

  test('warmDirectSidecarAfterUsbGrant returns false when no Canon is attached',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'isCameraPresent') return false;
      return null;
    });
    final ok = await warmDirectSidecarAfterUsbGrant(
      config: const CameraSidecarConfig(
        enabled: true,
        baseUrl: 'http://127.0.0.1:8791',
        livePreviewEnabled: true,
        connectionMode: CameraConnectionMode.direct,
      ),
      timeout: const Duration(milliseconds: 50),
      pollInterval: const Duration(milliseconds: 5),
    );
    expect(ok, isFalse);
  });

  test('isDirectCanonHardwareAvailable is false without a USB body', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'isCameraPresent') return false;
      return null;
    });
    expect(
      await isDirectCanonHardwareAvailable(
        settings: AppSettingsModel(cameraConnectionMode: 'direct'),
      ),
      isFalse,
    );
    expect(
      await isDirectCanonHardwareAvailable(
        settings: AppSettingsModel(
          cameraConnectionMode: 'pi',
          cameraEnabled: true,
          cameraSidecarHost: '10.0.0.5',
        ),
      ),
      isFalse,
    );
  });

  test('isDirectCanonHardwareAvailable is true when USB Canon is present', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'isCameraPresent') return true;
      return null;
    });
    expect(
      await isDirectCanonHardwareAvailable(
        settings: AppSettingsModel(cameraConnectionMode: 'direct'),
      ),
      isTrue,
    );
    expect(await isDirectCanonHardwareAvailable(), isTrue);
  });

  test('isDirectCanonHardwareAvailable is false off Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(await isDirectCanonHardwareAvailable(), isFalse);
  });

  test('primeCanonUsbOnTermsLaunch no-ops when no Canon is attached', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    var requested = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'isCameraPresent') return false;
      if (call.method == 'requestUsbPermission') {
        requested = true;
        return false;
      }
      return null;
    });
    final ok = await primeCanonUsbOnTermsLaunch(
      settings: AppSettingsModel(cameraConnectionMode: 'direct'),
    );
    expect(ok, isTrue);
    expect(requested, isFalse);
  });

  test('primeCanonUsbOnTermsLaunch warms direct sidecar after USB grant', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'isCameraPresent') return true;
      if (call.method == 'hasUsbPermission') return true;
      if (call.method == 'getState') return 'running';
      return null;
    });
    final client = MockClient((request) async {
      return http.Response(
        '{"ok":true,"connected":true,"backend":"edsdk"}',
        200,
      );
    });
    final ok = await primeCanonUsbOnTermsLaunch(
      settings: AppSettingsModel(cameraConnectionMode: 'direct'),
      client: client,
    );
    expect(ok, isTrue);
  });

  group('direct PTP Terms USB priming', () {
    const ptpChannel = MethodChannel(DirectPtpCameraService.methodChannelName);

    tearDown(() {
      messenger.setMockMethodCallHandler(ptpChannel, null);
    });

    test('isDirectPtpBooth honours ZenAI mode', () {
      expect(
        isDirectPtpBooth(
          AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
        ),
        isTrue,
      );
      expect(
        isDirectPtpBooth(
          AppSettingsModel(cameraConnectionMode: 'direct'),
        ),
        isFalse,
      );
    });

    test('isOnDeviceCanonUsbBooth covers EDSDK and PTP', () {
      expect(
        isOnDeviceCanonUsbBooth(
          AppSettingsModel(cameraConnectionMode: 'direct'),
        ),
        isTrue,
      );
      expect(
        isOnDeviceCanonUsbBooth(
          AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
        ),
        isTrue,
      );
      expect(
        isOnDeviceCanonUsbBooth(
          AppSettingsModel(
            cameraConnectionMode: 'pi',
            cameraEnabled: true,
            cameraSidecarHost: '10.0.0.1',
          ),
        ),
        isFalse,
      );
    });

    test('ensureDirectPtpUsbOnTerms no-ops off Android and non-PTP booths', () async {
      final okWeb = await ensureDirectPtpUsbOnTerms(
        settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
        camera: DirectPtpCameraService(isAndroid: () => false),
      );
      expect(okWeb, isTrue);

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final okDirect = await ensureDirectPtpUsbOnTerms(
        settings: AppSettingsModel(cameraConnectionMode: 'direct'),
        camera: DirectPtpCameraService(isAndroid: () => true),
      );
      expect(okDirect, isTrue);
    });

    test('ensureDirectPtpUsbOnTerms returns false when no USB host', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      messenger.setMockMethodCallHandler(ptpChannel, (call) async {
        if (call.method == 'hasUsbHost') return false;
        return null;
      });
      final ok = await ensureDirectPtpUsbOnTerms(
        settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
        camera: DirectPtpCameraService(isAndroid: () => true),
      );
      expect(ok, isFalse);
    });

    test('ensureDirectPtpUsbOnTerms returns false when no camera attached', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      messenger.setMockMethodCallHandler(ptpChannel, (call) async {
        if (call.method == 'hasUsbHost') return true;
        if (call.method == 'probeDevice') return null;
        return null;
      });
      final ok = await ensureDirectPtpUsbOnTerms(
        settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
        camera: DirectPtpCameraService(isAndroid: () => true),
      );
      expect(ok, isFalse);
    });

    test('ensureDirectPtpUsbOnTerms skips connect when permission already held', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var connectCalls = 0;
      messenger.setMockMethodCallHandler(ptpChannel, (call) async {
        switch (call.method) {
          case 'hasUsbHost':
            return true;
          case 'probeDevice':
            return {
              'deviceName': '/dev/1',
              'vendorId': 0x04a9,
              'productId': 1,
              'hasPermission': true,
            };
          case 'connect':
            connectCalls++;
            return null;
          default:
            return null;
        }
      });
      final ok = await ensureDirectPtpUsbOnTerms(
        settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
        camera: DirectPtpCameraService(isAndroid: () => true),
      );
      expect(ok, isTrue);
      expect(connectCalls, 0);
    });

    test('ensureDirectPtpUsbOnTerms connects when permission missing', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      var connectCalls = 0;
      messenger.setMockMethodCallHandler(ptpChannel, (call) async {
        switch (call.method) {
          case 'hasUsbHost':
            return true;
          case 'probeDevice':
            return {
              'deviceName': '/dev/1',
              'vendorId': 0x04a9,
              'productId': 1,
              'hasPermission': false,
            };
          case 'connect':
            connectCalls++;
            return {
              'state': 'Ready',
              'label': 'Ready',
              'isOperational': true,
              'isFault': false,
            };
          default:
            return null;
        }
      });

      final ok = await ensureDirectPtpUsbOnTerms(
        settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
        camera: DirectPtpCameraService(isAndroid: () => true),
      );
      expect(ok, isTrue);
      expect(connectCalls, 1);
    });

    test('ensureDirectPtpUsbOnTerms returns false when permission denied', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      messenger.setMockMethodCallHandler(ptpChannel, (call) async {
        switch (call.method) {
          case 'hasUsbHost':
            return true;
          case 'probeDevice':
            return {
              'deviceName': '/dev/1',
              'vendorId': 0x04a9,
              'productId': 1,
              'hasPermission': false,
            };
          case 'connect':
            return {
              'state': 'PermissionDenied',
              'label': 'Permission denied',
            };
          default:
            return null;
        }
      });
      final ok = await ensureDirectPtpUsbOnTerms(
        settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
        camera: DirectPtpCameraService(isAndroid: () => true),
      );
      expect(ok, isFalse);
    });

    test('warmDirectPtpOnTerms returns true when already operational', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      messenger.setMockMethodCallHandler(ptpChannel, (call) async {
        if (call.method == 'status') {
          return {'state': 'Ready', 'label': 'Ready'};
        }
        return null;
      });
      final ok = await warmDirectPtpOnTerms(
        settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
        camera: DirectPtpCameraService(isAndroid: () => true),
        timeout: const Duration(milliseconds: 50),
      );
      expect(ok, isTrue);
    });

    test('warmDirectPtpOnTerms connects when permission already held', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var statusCalls = 0;
      messenger.setMockMethodCallHandler(ptpChannel, (call) async {
        switch (call.method) {
          case 'status':
            statusCalls++;
            return {'state': 'NoDevice', 'label': 'No device'};
          case 'probeDevice':
            return {
              'deviceName': '/dev/1',
              'vendorId': 0x04a9,
              'productId': 1,
              'hasPermission': true,
            };
          case 'connect':
            return {'state': 'Ready', 'label': 'Ready'};
          default:
            return null;
        }
      });
      final ok = await warmDirectPtpOnTerms(
        settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
        camera: DirectPtpCameraService(isAndroid: () => true),
        timeout: const Duration(milliseconds: 50),
        pollInterval: const Duration(milliseconds: 5),
      );
      expect(ok, isTrue);
      expect(statusCalls, greaterThan(0));
    });

    test('warmDirectPtpOnTerms returns false when permission denied on connect', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      messenger.setMockMethodCallHandler(ptpChannel, (call) async {
        switch (call.method) {
          case 'status':
            return {'state': 'NoDevice', 'label': 'No device'};
          case 'probeDevice':
            return {
              'deviceName': '/dev/1',
              'vendorId': 0x04a9,
              'productId': 1,
              'hasPermission': false,
            };
          case 'connect':
            return {'state': 'PermissionDenied', 'label': 'Denied'};
          default:
            return null;
        }
      });
      final ok = await warmDirectPtpOnTerms(
        settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
        camera: DirectPtpCameraService(isAndroid: () => true),
        timeout: const Duration(milliseconds: 50),
        pollInterval: const Duration(milliseconds: 5),
      );
      expect(ok, isFalse);
    });

    test('warmDirectPtpOnTerms times out when camera never connects', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      messenger.setMockMethodCallHandler(ptpChannel, (call) async {
        if (call.method == 'status') {
          return {'state': 'NoDevice', 'label': 'No device'};
        }
        if (call.method == 'probeDevice') return null;
        return null;
      });
      final ok = await warmDirectPtpOnTerms(
        settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
        camera: DirectPtpCameraService(isAndroid: () => true),
        timeout: const Duration(milliseconds: 20),
        pollInterval: const Duration(milliseconds: 5),
      );
      expect(ok, isFalse);
    });

    test('warmDirectPtpOnTerms no-ops off Android', () async {
      final ok = await warmDirectPtpOnTerms(
        settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
        camera: DirectPtpCameraService(isAndroid: () => false),
      );
      expect(ok, isFalse);
    });

    test('primeDirectPtpOnTermsLaunch no-ops for EDSDK direct booths', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      var ptpCalls = 0;
      messenger.setMockMethodCallHandler(ptpChannel, (call) async {
        ptpCalls++;
        return null;
      });

      final ok = await primeDirectPtpOnTermsLaunch(
        settings: AppSettingsModel(cameraConnectionMode: 'direct'),
        camera: DirectPtpCameraService(isAndroid: () => true),
      );
      expect(ok, isTrue);
      expect(ptpCalls, 0);
    });

    test('primeDirectPtpOnTermsLaunch warms PTP after USB grant', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      messenger.setMockMethodCallHandler(ptpChannel, (call) async {
        switch (call.method) {
          case 'hasUsbHost':
            return true;
          case 'probeDevice':
            return {
              'deviceName': '/dev/1',
              'vendorId': 0x04a9,
              'productId': 1,
              'hasPermission': false,
            };
          case 'connect':
            return {'state': 'Ready', 'label': 'Ready'};
          case 'status':
            return {'state': 'Ready', 'label': 'Ready'};
          default:
            return null;
        }
      });
      final ok = await primeDirectPtpOnTermsLaunch(
        settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
        camera: DirectPtpCameraService(isAndroid: () => true),
      );
      expect(ok, isTrue);
    });

    test('isDirectPtpReadyForTerms true when status is operational', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      messenger.setMockMethodCallHandler(ptpChannel, (call) async {
        if (call.method == 'status') {
          return {
            'state': 'Ready',
            'label': 'Ready',
            'isOperational': true,
            'isFault': false,
          };
        }
        return null;
      });

      final ok = await isDirectPtpReadyForTerms(
        settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
        camera: DirectPtpCameraService(isAndroid: () => true),
      );
      expect(ok, isTrue);
    });

    test('isDirectPtpReadyForTerms true when probe reports permission', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      messenger.setMockMethodCallHandler(ptpChannel, (call) async {
        switch (call.method) {
          case 'status':
            return {'state': 'NoDevice', 'label': 'No device'};
          case 'probeDevice':
            return {
              'deviceName': '/dev/1',
              'vendorId': 0x04a9,
              'productId': 1,
              'hasPermission': true,
            };
          default:
            return null;
        }
      });
      final ok = await isDirectPtpReadyForTerms(
        settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
        camera: DirectPtpCameraService(isAndroid: () => true),
      );
      expect(ok, isTrue);
    });

    test('isDirectPtpReadyForTerms false when not a PTP booth', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final ok = await isDirectPtpReadyForTerms(
        settings: AppSettingsModel(cameraConnectionMode: 'direct'),
        camera: DirectPtpCameraService(isAndroid: () => true),
      );
      expect(ok, isFalse);
    });

    test('prepareDirectPtpPoseSession syncs stack and connects before capture', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      var connectCalls = 0;
      messenger.setMockMethodCallHandler(ptpChannel, (call) async {
        switch (call.method) {
          case 'setPreferredStack':
            return {'stack': 'ptp', 'changed': true};
          case 'status':
            return {'state': 'Error', 'label': 'Error', 'message': 'stale'};
          case 'disconnect':
            return null;
          case 'connect':
            connectCalls++;
            return {'state': 'Ready', 'label': 'Ready'};
          default:
            return null;
        }
      });

      final ok = await prepareDirectPtpPoseSession(
        settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
        camera: DirectPtpCameraService(isAndroid: () => true),
      );
      expect(ok, isTrue);
      expect(connectCalls, 1);
    });

    test('prepareDirectPtpPoseSession returns true when already operational', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      var connectCalls = 0;
      messenger.setMockMethodCallHandler(ptpChannel, (call) async {
        switch (call.method) {
          case 'setPreferredStack':
            return {'stack': 'ptp', 'changed': false};
          case 'status':
            return {'state': 'Ready', 'label': 'Ready'};
          case 'connect':
            connectCalls++;
            return null;
          default:
            return null;
        }
      });

      final ok = await prepareDirectPtpPoseSession(
        settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
        camera: DirectPtpCameraService(isAndroid: () => true),
      );
      expect(ok, isTrue);
      expect(connectCalls, 0);
    });

    test('prepareDirectPtpPoseSession no-ops for EDSDK booths', () async {
      expect(
        await prepareDirectPtpPoseSession(
          settings: AppSettingsModel(cameraConnectionMode: 'direct'),
          camera: DirectPtpCameraService(isAndroid: () => true),
        ),
        isTrue,
      );
    });

    test('prepareDirectPtpPoseSession returns false when permission denied', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      messenger.setMockMethodCallHandler(ptpChannel, (call) async {
        switch (call.method) {
          case 'setPreferredStack':
            return {'stack': 'ptp', 'changed': false};
          case 'status':
            return {'state': 'NoDevice', 'label': 'No device'};
          case 'connect':
            return {'state': 'PermissionDenied', 'label': 'Denied'};
          default:
            return null;
        }
      });
      final ok = await prepareDirectPtpPoseSession(
        settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
        camera: DirectPtpCameraService(isAndroid: () => true),
        timeout: const Duration(milliseconds: 20),
        pollInterval: const Duration(milliseconds: 5),
      );
      expect(ok, isFalse);
    });

    test('prepareDirectPtpPoseSession disconnects faulted connect attempts', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      var connectCalls = 0;
      var disconnectCalls = 0;
      messenger.setMockMethodCallHandler(ptpChannel, (call) async {
        switch (call.method) {
          case 'setPreferredStack':
            return {'stack': 'ptp', 'changed': false};
          case 'status':
            return {'state': 'NoDevice', 'label': 'No device'};
          case 'connect':
            connectCalls++;
            if (connectCalls == 1) {
              return {'state': 'Error', 'label': 'Error', 'message': 'busy'};
            }
            return {'state': 'Ready', 'label': 'Ready'};
          case 'disconnect':
            disconnectCalls++;
            return null;
          default:
            return null;
        }
      });

      final ok = await prepareDirectPtpPoseSession(
        settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
        camera: DirectPtpCameraService(isAndroid: () => true),
        pollInterval: const Duration(milliseconds: 1),
      );
      expect(ok, isTrue);
      expect(disconnectCalls, 1);
      expect(connectCalls, 2);
    });

    test('direct PTP helpers use default camera service when omitted', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      messenger.setMockMethodCallHandler(ptpChannel, (call) async {
        switch (call.method) {
          case 'hasUsbHost':
            return false;
          case 'status':
            return {'state': 'NoDevice', 'label': 'No device'};
          default:
            return null;
        }
      });

      final settings = AppSettingsModel(cameraConnectionMode: 'direct_ptp');
      expect(await ensureDirectPtpUsbOnTerms(settings: settings), isTrue);
      expect(await warmDirectPtpOnTerms(settings: settings), isFalse);
      expect(await isDirectPtpReadyForTerms(settings: settings), isFalse);
      expect(await prepareDirectPtpPoseSession(settings: settings), isFalse);
      expect(await isDirectPtpHardwareAvailable(settings: settings), isFalse);
    });

    test('isDirectPtpHardwareAvailable is false off Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(
        await isDirectPtpHardwareAvailable(
          settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
          camera: DirectPtpCameraService(isAndroid: () => true),
        ),
        isFalse,
      );
    });

    test('isDirectPtpHardwareAvailable is false when not a PTP booth', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(
        await isDirectPtpHardwareAvailable(
          settings: AppSettingsModel(cameraConnectionMode: 'direct'),
          camera: DirectPtpCameraService(isAndroid: () => true),
        ),
        isFalse,
      );
    });

    test('isDirectPtpHardwareAvailable is false when PTP is unsupported',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(
        await isDirectPtpHardwareAvailable(
          settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
          camera: DirectPtpCameraService(isAndroid: () => false),
        ),
        isFalse,
      );
    });

    test('isDirectPtpHardwareAvailable is false without a USB host', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      messenger.setMockMethodCallHandler(ptpChannel, (call) async {
        if (call.method == 'hasUsbHost') return false;
        return null;
      });
      expect(
        await isDirectPtpHardwareAvailable(
          settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
          camera: DirectPtpCameraService(isAndroid: () => true),
        ),
        isFalse,
      );
    });

    test('isDirectPtpHardwareAvailable is false when no body is attached',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      messenger.setMockMethodCallHandler(ptpChannel, (call) async {
        if (call.method == 'hasUsbHost') return true;
        if (call.method == 'probeDevice') return null;
        return null;
      });
      expect(
        await isDirectPtpHardwareAvailable(
          settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
          camera: DirectPtpCameraService(isAndroid: () => true),
        ),
        isFalse,
      );
    });

    test('isDirectPtpHardwareAvailable is true when a Canon is on USB',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      messenger.setMockMethodCallHandler(ptpChannel, (call) async {
        switch (call.method) {
          case 'hasUsbHost':
            return true;
          case 'probeDevice':
            return {
              'deviceName': '/dev/1',
              'vendorId': 0x04a9,
              'productId': 1,
              'hasPermission': true,
            };
          default:
            return null;
        }
      });
      expect(
        await isDirectPtpHardwareAvailable(
          settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
          camera: DirectPtpCameraService(isAndroid: () => true),
        ),
        isTrue,
      );
    });
  });

  group('Terms re-entry probes', () {
    const ptpChannel = MethodChannel(DirectPtpCameraService.methodChannelName);

    tearDown(() => messenger.setMockMethodCallHandler(ptpChannel, null));

    void asAndroid() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
    }

    test('permission held is false off Android', () async {
      expect(
        await isOnDeviceCanonUsbPermissionHeld(
          settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
        ),
        isFalse,
      );
    });

    test('permission held follows PTP readiness', () async {
      asAndroid();
      messenger.setMockMethodCallHandler(ptpChannel, (call) async {
        if (call.method == 'status') {
          return {'state': 'Ready', 'label': 'Ready'};
        }
        return null;
      });
      expect(
        await isOnDeviceCanonUsbPermissionHeld(
          settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
          camera: DirectPtpCameraService(isAndroid: () => true),
        ),
        isTrue,
      );
    });

    test('permission held is false when PTP has no device', () async {
      asAndroid();
      messenger.setMockMethodCallHandler(ptpChannel, (call) async {
        switch (call.method) {
          case 'status':
            return {'state': 'NoDevice', 'label': 'No device'};
          default:
            return null;
        }
      });
      expect(
        await isOnDeviceCanonUsbPermissionHeld(
          settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
          camera: DirectPtpCameraService(isAndroid: () => true),
        ),
        isFalse,
      );
    });

    test('permission held is false for non-Canon booths', () async {
      asAndroid();
      expect(
        await isOnDeviceCanonUsbPermissionHeld(
          settings: AppSettingsModel(
            cameraConnectionMode: 'pi',
            cameraEnabled: true,
            cameraSidecarHost: '10.0.0.5',
          ),
        ),
        isFalse,
      );
    });

    test('permission held asks the sidecar channel for EDSDK booths', () async {
      asAndroid();
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'hasUsbPermission') return true;
        return null;
      });
      expect(
        await isOnDeviceCanonUsbPermissionHeld(
          settings: AppSettingsModel(cameraConnectionMode: 'direct'),
        ),
        isTrue,
      );
      expect(calls, ['hasUsbPermission']);
    });

    test('still ready is false off Android', () async {
      expect(
        await isOnDeviceCanonBoothStillReady(
          settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
        ),
        isFalse,
      );
    });

    test('still ready follows PTP readiness', () async {
      asAndroid();
      messenger.setMockMethodCallHandler(ptpChannel, (call) async {
        if (call.method == 'status') {
          return {'state': 'Ready', 'label': 'Ready'};
        }
        return null;
      });
      expect(
        await isOnDeviceCanonBoothStillReady(
          settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
          camera: DirectPtpCameraService(isAndroid: () => true),
        ),
        isTrue,
      );
    });

    test('still ready is false for non-Canon booths', () async {
      asAndroid();
      expect(
        await isOnDeviceCanonBoothStillReady(
          settings: AppSettingsModel(
            cameraConnectionMode: 'pi',
            cameraEnabled: true,
            cameraSidecarHost: '10.0.0.5',
          ),
        ),
        isFalse,
      );
    });

    test('still ready is true when the EDSDK sidecar answers', () async {
      asAndroid();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'isCameraPresent') return true;
        if (call.method == 'getState') return 'running';
        return null;
      });
      final client = MockClient(
        (_) async => http.Response('{"ok":true,"connected":true}', 200),
      );
      expect(
        await isOnDeviceCanonBoothStillReady(
          settings: AppSettingsModel(cameraConnectionMode: 'direct'),
          client: client,
          sidecarTimeout: const Duration(milliseconds: 200),
        ),
        isTrue,
      );
    });

    test('still ready gives up quickly on a dead sidecar', () async {
      asAndroid();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getState') return 'idle';
        return null;
      });
      final client = MockClient((_) async => throw Exception('refused'));
      expect(
        await isOnDeviceCanonBoothStillReady(
          settings: AppSettingsModel(cameraConnectionMode: 'direct'),
          client: client,
          sidecarTimeout: const Duration(milliseconds: 30),
        ),
        isFalse,
      );
    });
  });

  group('isDirectPtpHardwareAvailable', () {
    test('false off Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(await isDirectPtpHardwareAvailable(), isFalse);
    });

    test('false when the booth is not direct_ptp', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(
        await isDirectPtpHardwareAvailable(
          settings: AppSettingsModel(cameraConnectionMode: 'pi'),
          camera: DirectPtpCameraService(isAndroid: () => true),
        ),
        isFalse,
      );
    });

    test('false when the native service is unsupported', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(
        await isDirectPtpHardwareAvailable(
          settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
          camera: DirectPtpCameraService(isAndroid: () => false),
        ),
        isFalse,
      );
    });

    test('false without USB host', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const ptpChannel = MethodChannel('com.srisarani.fotozenai/canon_ptp');
      messenger.setMockMethodCallHandler(ptpChannel, (call) async {
        if (call.method == 'hasUsbHost') return false;
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(ptpChannel, null));
      expect(
        await isDirectPtpHardwareAvailable(
          settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
          camera: DirectPtpCameraService(isAndroid: () => true),
        ),
        isFalse,
      );
    });

    test('true when a device is on the bus', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const ptpChannel = MethodChannel('com.srisarani.fotozenai/canon_ptp');
      messenger.setMockMethodCallHandler(ptpChannel, (call) async {
        if (call.method == 'hasUsbHost') return true;
        if (call.method == 'probeDevice') {
          return {
            'deviceName': 'EOS',
            'vendorId': 1,
            'productId': 2,
            'hasPermission': true,
          };
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(ptpChannel, null));
      expect(
        await isDirectPtpHardwareAvailable(
          settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
          camera: DirectPtpCameraService(isAndroid: () => true),
        ),
        isTrue,
      );
    });

    test('uses the default camera service when omitted', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(
        await isDirectPtpHardwareAvailable(
          settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
        ),
        isFalse,
      );
    });
  });
}
