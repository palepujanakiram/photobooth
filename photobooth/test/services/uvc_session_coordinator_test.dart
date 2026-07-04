import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/uvc_session_coordinator.dart';
import 'package:photobooth/utils/app_device_type.dart';

void main() {
  tearDown(UvcSessionCoordinator.resetForTest);

  test('waitBeforeOpen is instant before any UVC session', () async {
    final sw = Stopwatch()..start();
    await UvcSessionCoordinator.waitBeforeOpen();
    expect(sw.elapsed, lessThan(const Duration(milliseconds: 50)));
  });

  test('waitBeforeOpen waits for teardown and settle after UVC session', () async {
    final gate = Completer<void>();
    UvcSessionCoordinator.markSessionStarted();
    UvcSessionCoordinator.trackTeardown(gate.future);

    var settled = false;
    final waitFuture = UvcSessionCoordinator.waitBeforeOpen(
      deviceType: AppDeviceType.androidTablet,
    ).then((_) => settled = true);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(settled, isFalse);

    gate.complete();
    await waitFuture;
    expect(settled, isTrue);
  });
}
