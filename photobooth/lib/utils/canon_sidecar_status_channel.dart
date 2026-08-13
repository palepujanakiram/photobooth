import 'package:flutter/services.dart';

/// Queries native Canon sidecar and camera USB state on Android.
/// Returns safe defaults on non-Android platforms or when the channel is unavailable.
class CanonSidecarStatusChannel {
  static const _channel =
      MethodChannel('com.srisarani.fotozenai/canon_sidecar_status');

  /// Sidecar process state: `"idle"` | `"running"` | `"crashed"` |
  /// `"max_restarts"` | `"unsupported_abi"`.
  static Future<String> getState() async {
    try {
      final result = await _channel.invokeMethod<String>('getState');
      return result ?? 'idle';
    } on Object {
      return 'idle';
    }
  }

  /// True if the Canon DSLR is present in the Android USB device list.
  static Future<bool> isCameraPresent() async {
    try {
      final result = await _channel.invokeMethod<bool>('isCameraPresent');
      return result ?? false;
    } on Object {
      return false;
    }
  }
}
