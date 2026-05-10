import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Timestamped phases for debugging web capture → upload → theme freezes.
///
/// **Chrome DevTools:** Console → filter by `WebFlow` (logger name).
/// **Flutter run:** lines appear in the terminal when using `-v` or normal run.
///
/// Call [reset] at the start of each user journey leg (shutter vs Continue).
class WebFlowTrace {
  WebFlowTrace._();

  static int _epochMs = 0;

  /// Start a new timeline (milliseconds relative to this call).
  static void reset({required String label}) {
    _epochMs = DateTime.now().millisecondsSinceEpoch;
    if (kDebugMode) {
      developer.log(
        '── reset ($label) at ${DateTime.now().toIso8601String()} ──',
        name: 'WebFlow',
      );
    }
  }

  /// One phase line: elapsed ms since [reset], phase name, optional detail.
  static void log(String phase, [String detail = '']) {
    if (!kDebugMode) return;
    if (_epochMs == 0) {
      _epochMs = DateTime.now().millisecondsSinceEpoch;
    }
    final dt = DateTime.now().millisecondsSinceEpoch - _epochMs;
    final pad = dt.toString().padLeft(6);
    final tail = detail.isEmpty ? '' : ' | $detail';
    developer.log('$pad ms  $phase$tail', name: 'WebFlow');
  }
}
