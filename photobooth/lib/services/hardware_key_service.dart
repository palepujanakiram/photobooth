import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android-only: listen to physical key events (e.g. Bluetooth clickers).
///
/// The native side emits events when enabled; see `android/.../MainActivity.kt`.
class HardwareKeyService {
  static const MethodChannel _channel = MethodChannel('photobooth/hardware_keys');

  static final StreamController<HardwareKeyEvent> _controller =
      StreamController<HardwareKeyEvent>.broadcast();

  static bool _initialized = false;

  static Stream<HardwareKeyEvent> get events {
    _ensureInitialized();
    return _controller.stream;
  }

  static Future<void> setEnabled(bool enabled) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _ensureInitialized();
    try {
      await _channel.invokeMethod<void>('setEnabled', {'enabled': enabled});
    } catch (_) {
      // Best-effort: if the native channel isn't wired, app should still work.
    }
  }

  static void _ensureInitialized() {
    if (_initialized) return;
    _initialized = true;

    if (defaultTargetPlatform != TargetPlatform.android) return;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onKey') {
        final args = call.arguments;
        if (args is Map) {
          final keyCode = (args['keyCode'] as int?) ?? -1;
          final action = (args['action'] as int?) ?? -1;
          final event = HardwareKeyEvent(
            keyCode: keyCode,
            action: action,
            timestampMs:
                (args['timestampMs'] is int) ? args['timestampMs'] as int : null,
          );
          if (!_controller.isClosed) {
            _controller.add(event);
          }
        }
      }
    });
  }
}

@immutable
class HardwareKeyEvent {
  const HardwareKeyEvent({
    required this.keyCode,
    required this.action,
    this.timestampMs,
  });

  /// Android keyCode (e.g. KEYCODE_VOLUME_UP=24, KEYCODE_VOLUME_DOWN=25).
  final int keyCode;

  /// Android action (KeyEvent.ACTION_DOWN=0, ACTION_UP=1).
  final int action;

  final int? timestampMs;

  bool get isActionDown => action == 0;
}

