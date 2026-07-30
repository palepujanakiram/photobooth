import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Serializes USB-heavy work (UVC capture/teardown, upload encode, DNP print)
/// so RAM peaks do not overlap on memory-constrained Android TV kiosks.
class UsbResourceGate {
  UsbResourceGate._();

  static Future<void> _mutex = Future<void>.value();

  /// Runs [work] after any prior exclusive USB work completes.
  static Future<T> runExclusive<T>(Future<T> Function() work) async {
    final previous = _mutex;
    final completer = Completer<void>();
    _mutex = completer.future;
    await previous;
    try {
      return await work();
    } finally {
      completer.complete();
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _mutex = Future<void>.value();
  }
}
