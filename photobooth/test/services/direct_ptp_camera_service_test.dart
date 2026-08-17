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
}
