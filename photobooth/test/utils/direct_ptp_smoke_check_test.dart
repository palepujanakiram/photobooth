import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/direct_ptp_camera_service.dart';
import 'package:photobooth/utils/direct_ptp_smoke_check.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(DirectPtpCameraService.methodChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  DirectPtpCameraService androidCamera() =>
      DirectPtpCameraService(isAndroid: () => true);

  const Duration tinyWindow = Duration(milliseconds: 40);
  const Duration noWait = Duration.zero;

  Map<Object?, Object?> deviceMap() => <Object?, Object?>{
        'deviceName': '/dev/bus/usb/001/003',
        'vendorId': 0x04A9,
        'productId': 0x32E9,
        'product': 'Canon Digital Camera',
        'hasPermission': true,
      };

  Map<Object?, Object?> readyStatus({String? productName}) =>
      <Object?, Object?>{
        'state': 'Ready',
        'label': 'Ready',
        if (productName != null) 'productName': productName,
        'isOperational': true,
      };

  void handle(Future<Object?>? Function(MethodCall call) responder) {
    messenger.setMockMethodCallHandler(channel, responder);
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('parseDirectPtpSmokeRequested', () {
    test('accepts the lab dart-define aliases', () {
      expect(parseDirectPtpSmokeRequested('true'), isTrue);
      expect(parseDirectPtpSmokeRequested('1'), isTrue);
      expect(parseDirectPtpSmokeRequested('YES'), isTrue);
      expect(parseDirectPtpSmokeRequested('on'), isTrue);
      expect(parseDirectPtpSmokeRequested('capture'), isTrue);
      expect(parseDirectPtpSmokeRequested(''), isFalse);
      expect(parseDirectPtpSmokeRequested('no'), isFalse);
    });
  });

  group('parseDirectPtpSmokeCaptureRequested', () {
    test('is true only for capture', () {
      expect(parseDirectPtpSmokeCaptureRequested('capture'), isTrue);
      expect(parseDirectPtpSmokeCaptureRequested('true'), isFalse);
    });
  });

  group('runDirectPtpSmokeCheckIfRequested', () {
    test('the default dart-define leaves the check off', () {
      expect(directPtpSmokeRequested, isFalse);
      expect(directPtpSmokeCaptureRequested, isFalse);
    });

    test('returns immediately when not requested', () async {
      var called = false;
      handle((_) async {
        called = true;
        return null;
      });
      await runDirectPtpSmokeCheckIfRequested();
      expect(called, isFalse);
    });

    test('stops when the box has no USB host', () async {
      handle((call) async {
        if (call.method == 'hasUsbHost') return false;
        fail('must not continue without USB host');
      });
      await runDirectPtpSmokeCheckIfRequested(
        service: androidCamera(),
        requested: true,
      );
    });

    test('uses the default service when none is passed', () async {
      await runDirectPtpSmokeCheckIfRequested(requested: true);
    });

    test('times out when no camera appears', () async {
      handle((call) async {
        if (call.method == 'hasUsbHost') return true;
        if (call.method == 'probeDevice') return null;
        fail('unexpected ${call.method}');
      });
      await runDirectPtpSmokeCheckIfRequested(
        service: androidCamera(),
        requested: true,
        probeWindow: tinyWindow,
        probeInterval: noWait,
      );
    });

    test('connects after the camera shows up on a later probe', () async {
      var probes = 0;
      handle((call) async {
        switch (call.method) {
          case 'hasUsbHost':
            return true;
          case 'probeDevice':
            probes++;
            if (probes == 1) return null;
            return deviceMap();
          case 'connect':
            return readyStatus();
          default:
            fail('unexpected ${call.method}');
        }
      });
      await runDirectPtpSmokeCheckIfRequested(
        service: androidCamera(),
        requested: true,
        probeWindow: tinyWindow,
        probeInterval: noWait,
      );
      expect(probes, greaterThan(1));
    });

    test('logs a non-operational connect and skips capture', () async {
      handle((call) async {
        switch (call.method) {
          case 'hasUsbHost':
            return true;
          case 'probeDevice':
            return deviceMap();
          case 'connect':
            return <Object?, Object?>{
              'state': 'PermissionDenied',
              'label': 'Permission denied',
            };
          default:
            fail('unexpected ${call.method}');
        }
      });
      await runDirectPtpSmokeCheckIfRequested(
        service: androidCamera(),
        requested: true,
        probeWindow: tinyWindow,
        probeInterval: noWait,
      );
    });

    test('opens a capture session when capture is requested', () async {
      handle((call) async {
        switch (call.method) {
          case 'hasUsbHost':
            return true;
          case 'probeDevice':
            return deviceMap();
          case 'connect':
            return readyStatus(productName: 'Canon EOS 200D II');
          case 'runCaptureSession':
            return <Object?, Object?>{
              'status': 'completed',
              'shots': <Object?>[
                <Object?, Object?>{
                  'originalPath': '/data/o.JPG',
                  'displayPath': '/data/o.display.jpg',
                  'widthPx': 6000,
                  'heightPx': 4000,
                  'bytes': 12,
                },
              ],
            };
          default:
            fail('unexpected ${call.method}');
        }
      });
      await runDirectPtpSmokeCheckIfRequested(
        service: androidCamera(),
        requested: true,
        captureRequested: true,
        probeWindow: tinyWindow,
        probeInterval: noWait,
      );
    });

    test('logs a capture error without throwing', () async {
      handle((call) async {
        switch (call.method) {
          case 'hasUsbHost':
            return true;
          case 'probeDevice':
            return deviceMap();
          case 'connect':
            return readyStatus(productName: 'Canon EOS 200D II');
          case 'runCaptureSession':
            return <Object?, Object?>{
              'status': 'error',
              'errorCode': 'card_unavailable',
              'errorMessage': 'No SD card',
            };
          default:
            fail('unexpected ${call.method}');
        }
      });
      await runDirectPtpSmokeCheckIfRequested(
        service: androidCamera(),
        requested: true,
        captureRequested: true,
        probeWindow: tinyWindow,
        probeInterval: noWait,
      );
    });

    test('never lets a thrown probe stop startup', () async {
      await runDirectPtpSmokeCheckIfRequested(
        service: _ThrowingHostCamera(),
        requested: true,
      );
    });
  });
}

class _ThrowingHostCamera extends DirectPtpCameraService {
  _ThrowingHostCamera() : super(isAndroid: () => true);

  @override
  Future<bool> hasUsbHost() async => throw StateError('channel gone');
}
