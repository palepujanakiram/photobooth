import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/usb_resource_gate.dart';

void main() {
  tearDown(UsbResourceGate.resetForTest);

  test('runExclusive runs work serially', () async {
    final order = <int>[];
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();

    final first = UsbResourceGate.runExclusive(() async {
      order.add(1);
      firstStarted.complete();
      await releaseFirst.future;
      order.add(2);
    });

    await firstStarted.future;

    final second = UsbResourceGate.runExclusive(() async {
      order.add(3);
    });

    await Future<void>.delayed(Duration.zero);
    expect(order, [1]);

    releaseFirst.complete();
    await first;
    await second;

    expect(order, [1, 2, 3]);
  });
}
