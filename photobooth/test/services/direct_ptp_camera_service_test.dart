import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/direct_ptp_camera_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(DirectPtpCameraService.methodChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Installs a fake native side; [calls] records what Dart asked for.
  void handle(
    Future<Object?>? Function(MethodCall call) responder, {
    List<String>? calls,
  }) {
    messenger.setMockMethodCallHandler(channel, (call) {
      calls?.add(call.method);
      return responder(call);
    });
  }

  DirectPtpCameraService service() =>
      DirectPtpCameraService(isAndroid: () => true);

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('directPtpStateFromName', () {
    test('maps every known Kotlin state name', () {
      expect(directPtpStateFromName('Ready'), DirectPtpState.ready);
      expect(directPtpStateFromName('NoDevice'), DirectPtpState.noDevice);
      expect(
        directPtpStateFromName('PermissionDenied'),
        DirectPtpState.permissionDenied,
      );
      expect(directPtpStateFromName('RemoteMode'), DirectPtpState.remoteMode);
      expect(directPtpStateFromName('Detached'), DirectPtpState.detached);
      expect(
        directPtpStateFromName('NoUsbHostSupport'),
        DirectPtpState.noUsbHost,
      );
    });

    test('an unrecognised native state degrades to unknown, never throws', () {
      // The Kotlin sealed class will gain states before Dart has a use for them;
      // a build that crashes on an unfamiliar name would make the native side
      // impossible to evolve independently.
      expect(directPtpStateFromName('SomeFutureState'), DirectPtpState.unknown);
      expect(directPtpStateFromName(null), DirectPtpState.unknown);
    });
  });

  group('state classification', () {
    test('operational states are the ones that can accept a capture', () {
      expect(DirectPtpState.ready.isOperational, isTrue);
      expect(DirectPtpState.liveView.isOperational, isTrue);
      expect(DirectPtpState.remoteMode.isOperational, isTrue);
      expect(DirectPtpState.noDevice.isOperational, isFalse);
      expect(DirectPtpState.sessionOpen.isOperational, isFalse);
    });

    test('faults are distinguished from merely not-ready', () {
      expect(DirectPtpState.error.isFault, isTrue);
      expect(DirectPtpState.permissionDenied.isFault, isTrue);
      expect(DirectPtpState.wedged.isFault, isTrue);
      expect(DirectPtpState.noUsbHost.isFault, isTrue);
      // Nothing plugged in is not a fault — it is the normal idle state.
      expect(DirectPtpState.noDevice.isFault, isFalse);
      expect(DirectPtpState.opened.isFault, isFalse);
    });
  });

  group('hasUsbHost', () {
    test('returns the native answer', () async {
      handle((_) async => true);
      expect(await service().hasUsbHost(), isTrue);
    });

    test('a native failure reads as no host rather than propagating', () async {
      handle((_) async => throw PlatformException(code: 'boom'));
      expect(await service().hasUsbHost(), isFalse);
    });

    test('never reaches the channel off Android', () async {
      final calls = <String>[];
      handle((_) async => true, calls: calls);
      final offAndroid = DirectPtpCameraService(isAndroid: () => false);
      expect(await offAndroid.hasUsbHost(), isFalse);
      expect(calls, isEmpty);
    });
  });

  group('probeDevice', () {
    test('parses the attached camera', () async {
      handle((_) async => <Object?, Object?>{
            'deviceName': '/dev/bus/usb/001/003',
            'vendorId': 0x04A9,
            'productId': 0x32E9,
            'manufacturer': 'Canon Inc.',
            'product': 'Canon Digital Camera',
            'hasPermission': true,
          });
      final device = await service().probeDevice();
      expect(device, isNotNull);
      expect(device!.vendorId, 0x04A9);
      expect(device.productId, 0x32E9);
      expect(device.product, 'Canon Digital Camera');
      expect(device.hasPermission, isTrue);
    });

    test('null means nothing suitable on the bus', () async {
      handle((_) async => null);
      expect(await service().probeDevice(), isNull);
    });

    test('a camera present without permission is still reported', () async {
      // The distinction this method exists for: present-but-unauthorised must
      // not look identical to absent.
      handle((_) async => <Object?, Object?>{
            'deviceName': '/dev/bus/usb/001/003',
            'vendorId': 0x04A9,
            'productId': 0x32E9,
            'hasPermission': false,
          });
      final device = await service().probeDevice();
      expect(device, isNotNull);
      expect(device!.hasPermission, isFalse);
      expect(device.toString(), contains('permission: false'));
    });

    test('a native failure reads as absent rather than propagating', () async {
      handle((_) async => throw PlatformException(code: 'busy'));
      expect(await service().probeDevice(), isNull);
    });
  });

  group('connect', () {
    test('a successful handshake surfaces Ready and the model', () async {
      handle((_) async => <Object?, Object?>{
            'state': 'Ready',
            'label': 'Ready',
            'productName': 'Canon EOS 200D II',
            'isOperational': true,
            'isFault': false,
            'timedOut': false,
          });
      final status = await service().connect();
      expect(status.state, DirectPtpState.ready);
      expect(status.productName, 'Canon EOS 200D II');
      expect(status.isOperational, isTrue);
      expect(status.timedOut, isFalse);
    });

    test('a refused permission dialog is a fault, not an exception', () async {
      handle((_) async => <Object?, Object?>{
            'state': 'PermissionDenied',
            'label': 'Permission denied',
            'deviceName': '/dev/bus/usb/001/003',
          });
      final status = await service().connect();
      expect(status.state, DirectPtpState.permissionDenied);
      expect(status.isFault, isTrue);
    });

    test('a slow negotiation reports timedOut with the observed state',
        () async {
      // Distinct from failure on purpose: "still negotiating" and "refused"
      // call for different operator responses.
      handle((_) async => <Object?, Object?>{
            'state': 'SessionOpen',
            'label': 'PTP session open',
            'timedOut': true,
          });
      final status = await service().connect();
      expect(status.state, DirectPtpState.sessionOpen);
      expect(status.timedOut, isTrue);
      expect(status.isFault, isFalse);
    });

    test('a platform exception becomes an error status, not a throw', () async {
      handle((_) async => throw PlatformException(
            code: 'connect_failed',
            message: 'endpoint halted',
          ));
      final status = await service().connect();
      expect(status.state, DirectPtpState.error);
      expect(status.message, contains('endpoint halted'));
    });

    test('off Android it reports unsupported without touching the channel',
        () async {
      final calls = <String>[];
      handle((_) async => null, calls: calls);
      final offAndroid = DirectPtpCameraService(isAndroid: () => false);
      final status = await offAndroid.connect();
      expect(status.state, DirectPtpState.noUsbHost);
      expect(calls, isEmpty);
    });
  });

  group('status', () {
    test('reports the current link state', () async {
      handle((_) async => <Object?, Object?>{
            'state': 'LiveView',
            'label': 'Live view',
          });
      final status = await service().status();
      expect(status.state, DirectPtpState.liveView);
      expect(status.isOperational, isTrue);
    });

    test('a missing map degrades to unknown', () async {
      handle((_) async => null);
      expect((await service().status()).state, DirectPtpState.unknown);
    });

    test('a platform exception becomes an error status, not a throw', () async {
      handle((_) async => throw PlatformException(code: 'offline'));
      final status = await service().status();
      expect(status.state, DirectPtpState.error);
      expect(status.label, 'Status failed');
      expect(status.message, contains('offline'));
    });
  });

  group('disconnect', () {
    test('invokes the native release', () async {
      final calls = <String>[];
      handle((_) async => null, calls: calls);
      await service().disconnect();
      expect(calls, contains('disconnect'));
    });

    test('never throws, so teardown cannot fail', () async {
      handle((_) async => throw PlatformException(code: 'gone'));
      await expectLater(service().disconnect(), completes);
    });
  });

  group('runCaptureSession', () {
    test('parses a completed session and passes the shot count through',
        () async {
      MethodCall? seen;
      handle((call) async {
        seen = call;
        return <Object?, Object?>{
          'status': 'completed',
          'shots': <Object?>[
            <Object?, Object?>{
              'originalPath': '/data/captures/0001_IMG_3001.JPG',
              'displayPath': '/data/captures/0001_IMG_3001.display.jpg',
              'widthPx': 6000,
              'heightPx': 4000,
              'bytes': 6542638,
              'capturedAtMs': 1755400000000,
            },
          ],
        };
      });

      final result = await service().runCaptureSession(shotCount: 4);

      expect(result.status, DirectPtpCaptureStatus.completed);
      expect(result.isCompleted, isTrue);
      expect(result.shots, hasLength(1));
      expect(result.shots.first.widthPx, 6000);
      expect(result.shots.first.bytes, 6542638);
      final args = seen!.arguments as Map<Object?, Object?>;
      expect(args['shotCount'], 4);
    });

    test('previewPath prefers the derivative, never the original', () async {
      // The whole point: a 6000x4000 original decoded in Dart is ~96 MB and an
      // instant OOM on the target box.
      const shot = DirectPtpShot(
        originalPath: '/data/o.JPG',
        displayPath: '/data/o.display.jpg',
      );
      expect(shot.previewPath, '/data/o.display.jpg');
    });

    test('previewPath falls back to the original when no derivative exists',
        () {
      const shot = DirectPtpShot(originalPath: '/data/o.JPG');
      expect(shot.previewPath, '/data/o.JPG');
    });

    test('a cancelled session is not an error and carries no shots', () async {
      handle((_) async => <Object?, Object?>{
            'status': 'cancelled',
            'shots': <Object?>[],
            'errorMessage': 'Back pressed',
          });
      final result = await service().runCaptureSession();
      expect(result.isCancelled, isTrue);
      expect(result.isCompleted, isFalse);
      expect(result.shots, isEmpty);
    });

    test('an error keeps the code separate from the message', () async {
      // Codes drive operator action — "put a card in the camera" is a different
      // response from "plug the camera in" — so they must not be flattened into
      // free text.
      handle((_) async => <Object?, Object?>{
            'status': 'error',
            'errorCode': 'card_unavailable',
            'errorMessage': 'No SD card',
          });
      final result = await service().runCaptureSession();
      expect(result.status, DirectPtpCaptureStatus.error);
      expect(result.errorCode, 'card_unavailable');
    });

    test('completed with zero shots does not count as completed', () async {
      // Guards against treating a lost result as a successful empty session.
      handle((_) async => <Object?, Object?>{
            'status': 'completed',
            'shots': <Object?>[],
          });
      expect((await service().runCaptureSession()).isCompleted, isFalse);
    });

    test('a platform exception becomes an error result, not a throw', () async {
      handle((_) async => throw PlatformException(code: 'boom'));
      final result = await service().runCaptureSession();
      expect(result.status, DirectPtpCaptureStatus.error);
      expect(result.errorCode, 'capture_failed');
    });

    test('off Android it reports unsupported without touching the channel',
        () async {
      final calls = <String>[];
      handle((_) async => null, calls: calls);
      final offAndroid = DirectPtpCameraService(isAndroid: () => false);
      final result = await offAndroid.runCaptureSession();
      expect(result.errorCode, 'unsupported_platform');
      expect(calls, isEmpty);
    });

    test('a malformed shots payload degrades to an empty list', () async {
      handle((_) async => <Object?, Object?>{
            'status': 'completed',
            'shots': 'not a list',
          });
      final result = await service().runCaptureSession();
      expect(result.shots, isEmpty);
    });
  });

  group('DirectPtpStatus.fromMap', () {
    test('tolerates a map missing every optional key', () async {
      final status =
          DirectPtpStatus.fromMap(const <Object?, Object?>{'state': 'Busy'});
      expect(status.state, DirectPtpState.busy);
      expect(status.label, '');
      expect(status.productName, isNull);
      expect(status.timedOut, isFalse);
    });

    test('value equality holds, so status can drive widget rebuilds', () {
      const a = DirectPtpStatus(state: DirectPtpState.ready, label: 'Ready');
      const b = DirectPtpStatus(state: DirectPtpState.ready, label: 'Ready');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('DirectPtpShot.toString', () {
    test('includes the original path and pixel size', () {
      const shot = DirectPtpShot(
        originalPath: '/data/o.JPG',
        widthPx: 6000,
        heightPx: 4000,
        bytes: 12,
      );
      expect(shot.toString(), contains('/data/o.JPG'));
      expect(shot.toString(), contains('6000x4000'));
    });
  });

  group('default platform probe', () {
    test('is unsupported on this VM', () {
      final camera = DirectPtpCameraService();
      expect(camera.isSupported, isFalse);
    });
  });

  group('setPreferredStack', () {
    test('persists ptp when the native side answers', () async {
      handle((call) async {
        expect(call.method, 'setPreferredStack');
        expect(call.arguments, {'stack': 'ptp'});
        return <String, Object?>{'stack': 'ptp', 'changed': true};
      });
      final result = await service().setPreferredStack(preferPtp: true);
      expect(result['stack'], 'ptp');
      expect(result['changed'], isTrue);
    });

    test('a missing map still reports the requested stack', () async {
      handle((_) async => null);
      final result = await service().setPreferredStack(preferPtp: false);
      expect(result['stack'], 'edsdk');
      expect(result['changed'], isFalse);
    });

    test('a platform exception does not throw', () async {
      handle((_) async => throw PlatformException(code: 'busy'));
      final result = await service().setPreferredStack(preferPtp: true);
      expect(result['stack'], 'ptp');
      expect(result['changed'], isFalse);
    });

    test('off Android it reports edsdk without touching the channel', () async {
      final calls = <String>[];
      handle((_) async => null, calls: calls);
      final offAndroid = DirectPtpCameraService(isAndroid: () => false);
      final result = await offAndroid.setPreferredStack(preferPtp: true);
      expect(result['stack'], 'edsdk');
      expect(calls, isEmpty);
    });
  });

  group('statusStream', () {
    test('is empty off Android', () async {
      final offAndroid = DirectPtpCameraService(isAndroid: () => false);
      expect(await offAndroid.statusStream().isEmpty, isTrue);
    });

    test('maps native events and ignores a malformed payload', () async {
      const statusChannel =
          EventChannel(DirectPtpCameraService.statusChannelName);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        statusChannel,
        MockStreamHandler.inline(
          onListen: (args, sink) {
            sink.success(<Object?, Object?>{'state': 'Ready'});
            sink.success('not-a-map');
            sink.endOfStream();
          },
        ),
      );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockStreamHandler(statusChannel, null),
      );

      final events = await service().statusStream().toList();
      expect(events, hasLength(2));
      expect(events.first.state, DirectPtpState.ready);
      expect(events.last.state, DirectPtpState.unknown);
    });
  });
}
