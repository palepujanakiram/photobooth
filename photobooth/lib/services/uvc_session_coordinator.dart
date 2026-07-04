import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../utils/app_device_type.dart';
import '../utils/uvc_capture_config.dart';

/// Tracks in-flight UVC native teardown so the next capture visit can wait for USB settle.
class UvcSessionCoordinator {
  UvcSessionCoordinator._();

  static Future<void> _lastTeardown = Future<void>.value();
  static bool _hadUvcSession = false;

  static const Duration _teardownWaitCap = Duration(seconds: 3);

  /// True after any UVC feed was opened or torn down this process lifetime.
  static bool get hadPriorSession => _hadUvcSession;

  /// Registers native UVC release work (screen dispose, Continue exit, retake).
  static void trackTeardown(Future<void> future) {
    _hadUvcSession = true;
    _lastTeardown = future.catchError((Object _, StackTrace __) {});
  }

  /// Called when a UVC live feed opens successfully.
  static void markSessionStarted() {
    _hadUvcSession = true;
  }

  /// After a prior UVC session, wait for teardown (capped) then a short USB settle.
  static Future<void> waitBeforeOpen({AppDeviceType? deviceType}) async {
    if (!_hadUvcSession) return;
    try {
      await _lastTeardown.timeout(_teardownWaitCap);
    } on TimeoutException {
      // Do not block the next guest if native teardown stalls.
    }
    await Future<void>.delayed(UvcCaptureConfig.postDisposeDelay);
  }

  @visibleForTesting
  static void resetForTest() {
    _lastTeardown = Future<void>.value();
    _hadUvcSession = false;
  }
}
