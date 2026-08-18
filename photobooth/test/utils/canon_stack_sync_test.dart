import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/services/direct_ptp_camera_service.dart';
import 'package:photobooth/utils/canon_stack_sync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(DirectPtpCameraService.methodChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  DirectPtpCameraService androidCamera() =>
      DirectPtpCameraService(isAndroid: () => true);

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('asks native for PTP when ZenAI mode is direct_ptp', () async {
    Object? seen;
    messenger.setMockMethodCallHandler(channel, (call) async {
      seen = call.arguments;
      return <String, Object?>{'stack': 'ptp', 'changed': true};
    });

    await syncCanonCameraStackForSettings(
      AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
      camera: androidCamera(),
    );
    expect(seen, {'stack': 'ptp'});
  });

  test('asks native for EDSDK when mode is direct USB', () async {
    Object? seen;
    messenger.setMockMethodCallHandler(channel, (call) async {
      seen = call.arguments;
      return <String, Object?>{'stack': 'edsdk', 'changed': false};
    });

    await syncCanonCameraStackForSettings(
      AppSettingsModel(cameraConnectionMode: 'direct'),
      camera: androidCamera(),
    );
    expect(seen, {'stack': 'edsdk'});
  });

  test('a missing camera uses the default service and does not throw', () async {
    await expectLater(syncCanonCameraStackForSettings(null), completes);
  });

  test('a native failure is logged rather than thrown', () async {
    await expectLater(
      syncCanonCameraStackForSettings(
        AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
        camera: _ThrowingStackCamera(),
      ),
      completes,
    );
  });
}

class _ThrowingStackCamera extends DirectPtpCameraService {
  _ThrowingStackCamera() : super(isAndroid: () => true);

  @override
  Future<Map<String, Object?>> setPreferredStack({required bool preferPtp}) {
    throw StateError('channel gone');
  }
}
