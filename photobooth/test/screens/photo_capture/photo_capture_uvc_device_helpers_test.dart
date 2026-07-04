import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_uvc_device_helpers.dart';
import 'package:uvccamera/uvccamera.dart';

void main() {
  const deviceA = UvcCameraDevice(
    name: 'Canon EOS',
    vendorId: 1,
    productId: 2,
    deviceClass: 0,
    deviceSubclass: 0,
  );
  const deviceB = UvcCameraDevice(
    name: 'Canon EOS',
    vendorId: 1,
    productId: 2,
    deviceClass: 0,
    deviceSubclass: 0,
  );
  const deviceC = UvcCameraDevice(
    name: 'Other',
    vendorId: 9,
    productId: 9,
    deviceClass: 0,
    deviceSubclass: 0,
  );

  test('uvcDeviceMatches compares vendor, product, and name', () {
    expect(uvcDeviceMatches(deviceA, deviceB), isTrue);
    expect(uvcDeviceMatches(deviceA, deviceC), isFalse);
  });

  test('hasAttachedUvcDevices returns false on non-Android test host', () async {
    expect(await hasAttachedUvcDevices(), isFalse);
  });

  test('probeFirstUvcDevice returns null on non-Android test host', () async {
    final device = await probeFirstUvcDevice();
    expect(device, isNull);
  });
}
