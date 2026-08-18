import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photobooth/models/app_settings_model.dart';
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

  test('primeCanonUsbOnTermsLaunch warms direct sidecar after USB grant', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    messenger.setMockMethodCallHandler(channel, (call) async {
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
}
