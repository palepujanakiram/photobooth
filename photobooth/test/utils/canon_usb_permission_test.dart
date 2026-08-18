import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/utils/camera_sidecar_config.dart';
import 'package:photobooth/utils/canon_sidecar_status_channel.dart';
import 'package:photobooth/utils/canon_usb_permission.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.srisarani.fotozenai/canon_sidecar_status');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

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
}
