import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/direct_ptp_camera_service.dart';
import 'package:photobooth/utils/direct_ptp_smoke_check.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(DirectPtpCameraService.methodChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> calls;

  /// Fake native side. [probeResults] is consumed one entry per probeDevice, so
  /// a test can make the camera appear only after several polls.
  void handle({
    bool usbHost = true,
    List<Map<Object?, Object?>?> probeResults = const [null],
    Map<Object?, Object?>? connectResult,
    Map<Object?, Object?>? captureResult,
  }) {
    var probeIndex = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'hasUsbHost':
          return usbHost;
        case 'probeDevice':
          final r = probeIndex < probeResults.length
              ? probeResults[probeIndex]
              : probeResults.last;
          probeIndex++;
          return r;
        case 'connect':
          return connectResult;
        case 'runCaptureSession':
          return captureResult;
        default:
          return null;
      }
    });
  }

  DirectPtpCameraService service() =>
      DirectPtpCameraService(isAndroid: () => true);

  const device = <Object?, Object?>{
    'deviceName': '/dev/bus/usb/001/030',
    'vendorId': 0x04A9,
    'productId': 0x32E9,
    'product': 'Canon Digital Camera',
    'hasPermission': true,
  };

  const ready = <Object?, Object?>{
    'state': 'Ready',
    'label': 'Ready',
    'productName': 'Canon EOS 200D II',
  };

  setUp(() => calls = <String>[]);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('define parsing', () {
    test('the smoke check is off unless explicitly requested', () {
      // Connecting claims the USB interface and puts the body in remote mode,
      // which would be wrong on a booth still shooting with the device camera.
      expect(directPtpSmokeRequested, isFalse);
      expect(directPtpSmokeCaptureRequested, isFalse);
    });
  });

  group('runDirectPtpSmokeCheckIfRequested', () {
    test('does nothing at all when not requested', () async {
      handle();
      await runDirectPtpSmokeCheckIfRequested(
        service: service(),
        requested: false,
      );
      expect(calls, isEmpty);
    });

    test('stops early when the hardware cannot host USB', () async {
      handle(usbHost: false);
      await runDirectPtpSmokeCheckIfRequested(
        service: service(),
        requested: true,
        probeWindow: const Duration(milliseconds: 30),
        probeInterval: const Duration(milliseconds: 5),
      );
      expect(calls, ['hasUsbHost']);
    });

    test('polls until the camera appears, then connects', () async {
      // The whole point of the polling: the body auto-powers-off, so a single
      // probe at startup turns bring-up into a race with switching it on.
      handle(
        probeResults: const [null, null, device],
        connectResult: ready,
      );
      await runDirectPtpSmokeCheckIfRequested(
        service: service(),
        requested: true,
        captureRequested: false,
        probeWindow: const Duration(seconds: 5),
        probeInterval: const Duration(milliseconds: 5),
      );
      expect(calls.where((c) => c == 'probeDevice').length, 3);
      expect(calls, contains('connect'));
      expect(calls, isNot(contains('runCaptureSession')));
    });

    test('gives up when no camera appears inside the window', () async {
      handle(probeResults: const [null]);
      await runDirectPtpSmokeCheckIfRequested(
        service: service(),
        requested: true,
        probeWindow: const Duration(milliseconds: 40),
        probeInterval: const Duration(milliseconds: 5),
      );
      expect(calls, contains('probeDevice'));
      expect(calls, isNot(contains('connect')));
    });

    test('does not capture when the link never becomes operational', () async {
      handle(
        probeResults: const [device],
        connectResult: const <Object?, Object?>{
          'state': 'PermissionDenied',
          'label': 'Permission denied',
        },
      );
      await runDirectPtpSmokeCheckIfRequested(
        service: service(),
        requested: true,
        captureRequested: true,
        probeWindow: const Duration(seconds: 2),
        probeInterval: const Duration(milliseconds: 5),
      );
      expect(calls, contains('connect'));
      expect(calls, isNot(contains('runCaptureSession')));
    });

    test('opens the capture screen when capture is requested', () async {
      handle(
        probeResults: const [device],
        connectResult: ready,
        captureResult: const <Object?, Object?>{
          'status': 'completed',
          'shots': <Object?>[
            <Object?, Object?>{
              'originalPath': '/o.JPG',
              'displayPath': '/o.display.jpg',
              'widthPx': 6000,
              'heightPx': 4000,
              'bytes': 6000000,
            },
          ],
        },
      );
      await runDirectPtpSmokeCheckIfRequested(
        service: service(),
        requested: true,
        captureRequested: true,
        probeWindow: const Duration(seconds: 2),
        probeInterval: const Duration(milliseconds: 5),
      );
      expect(calls, contains('runCaptureSession'));
    });

    test('logs a capture error without throwing', () async {
      handle(
        probeResults: const [device],
        connectResult: ready,
        captureResult: const <Object?, Object?>{
          'status': 'error',
          'errorCode': 'card_unavailable',
          'errorMessage': 'No SD card',
        },
      );
      await expectLater(
        runDirectPtpSmokeCheckIfRequested(
          service: service(),
          requested: true,
          captureRequested: true,
          probeWindow: const Duration(seconds: 2),
          probeInterval: const Duration(milliseconds: 5),
        ),
        completes,
      );
    });

    test('a thrown native error cannot stop the app from starting', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        throw PlatformException(code: 'boom');
      });
      await expectLater(
        runDirectPtpSmokeCheckIfRequested(
          service: service(),
          requested: true,
          probeWindow: const Duration(milliseconds: 40),
          probeInterval: const Duration(milliseconds: 5),
        ),
        completes,
      );
    });
  });

  group('production gating', () {
    test('with no overrides it reads the compile-time defines and stays off',
        () async {
      // Exercises the `?? directPtpSmokeRequested` fallback, which is the path
      // every real build takes.
      handle();
      await runDirectPtpSmokeCheckIfRequested(service: service());
      expect(calls, isEmpty);
    });

    test('capture gating falls back to the define when not overridden',
        () async {
      // requested is forced on, captureRequested is not — so the capture step
      // must fall back to the define, which is off.
      handle(probeResults: const [device], connectResult: ready);
      await runDirectPtpSmokeCheckIfRequested(
        service: service(),
        requested: true,
        probeWindow: const Duration(seconds: 2),
        probeInterval: const Duration(milliseconds: 5),
      );
      expect(calls, contains('connect'));
      expect(calls, isNot(contains('runCaptureSession')));
    });
  });

  group('defensive construction and failure', () {
    test('builds its own service when none is injected', () async {
      // Production calls this with no arguments at all. Off Android there is no
      // bridge, so it must bail at the USB-host check without touching a channel.
      await expectLater(
        runDirectPtpSmokeCheckIfRequested(
          requested: true,
          probeWindow: const Duration(milliseconds: 20),
          probeInterval: const Duration(milliseconds: 5),
        ),
        completes,
      );
    });

    test('an unexpected throw is swallowed, never reaching runApp', () async {
      // The guarantee this catch exists for: a bring-up probe must not be able
      // to stop the app from starting.
      await expectLater(
        runDirectPtpSmokeCheckIfRequested(
          service: _ExplodingCameraService(),
          requested: true,
          probeWindow: const Duration(milliseconds: 20),
          probeInterval: const Duration(milliseconds: 5),
        ),
        completes,
      );
    });
  });
}

/// Fails in a way the service itself does not catch, to reach the outer guard.
class _ExplodingCameraService extends DirectPtpCameraService {
  _ExplodingCameraService() : super(isAndroid: () => true);

  @override
  Future<bool> hasUsbHost() async => throw StateError('bridge exploded');
}
