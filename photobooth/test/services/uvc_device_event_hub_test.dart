import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/uvc_device_event_hub.dart';
import 'package:uvccamera/uvccamera.dart';

void main() {
  tearDown(UvcDeviceEventHub.instance.resetForTest);

  test('fans out device events to multiple listeners', () async {
    final upstream = StreamController<UvcCameraDeviceEvent>();
    UvcDeviceEventHub.instance.testUpstream = upstream.stream;

    var a = 0;
    var b = 0;
    final subA = UvcDeviceEventHub.instance.listen((_) => a++);
    final subB = UvcDeviceEventHub.instance.stream.listen((_) => b++);

    upstream.add(
      const UvcCameraDeviceEvent(
        type: UvcCameraDeviceEventType.attached,
        device: UvcCameraDevice(
          name: 'cam',
          vendorId: 1,
          productId: 2,
          deviceClass: 0,
          deviceSubclass: 0,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(a, 1);
    expect(b, 1);

    await subA.cancel();
    await subB.cancel();
    await upstream.close();
  });

  test('cancelling a listener does not stop upstream for other listeners', () async {
    final upstream = StreamController<UvcCameraDeviceEvent>();
    UvcDeviceEventHub.instance.testUpstream = upstream.stream;

    var events = 0;
    final sub = UvcDeviceEventHub.instance.listen((_) => events++);
    await sub.cancel();

    upstream.add(
      const UvcCameraDeviceEvent(
        type: UvcCameraDeviceEventType.connected,
        device: UvcCameraDevice(
          name: 'cam',
          vendorId: 1,
          productId: 2,
          deviceClass: 0,
          deviceSubclass: 0,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(events, 0);
    await upstream.close();
  });
}
