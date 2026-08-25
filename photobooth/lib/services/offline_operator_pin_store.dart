import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

/// Booth operator PIN for offline cash confirm on the Pay screen.
///
/// Kept on-device so staff can release a print without leaving Pay / hitting Fly.
class OfflineOperatorPinStore {
  OfflineOperatorPinStore._();

  static const prefsKey = 'kiosk_offline_operator_pin';

  /// Factory default — change after install via [setPin].
  static const defaultPin = '2468';

  static String? _cached;

  @visibleForTesting
  static void resetCacheForTests() {
    _cached = null;
  }

  static Future<String> getPin() async {
    final cached = _cached;
    if (cached != null && cached.isNotEmpty) return cached;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(prefsKey)?.trim() ?? '';
    final pin = stored.isEmpty ? defaultPin : stored;
    _cached = pin;
    return pin;
  }

  static Future<void> setPin(String pin) async {
    final next = pin.trim();
    if (next.isEmpty) {
      throw ArgumentError('PIN must not be empty');
    }
    _cached = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, next);
  }

  static Future<bool> verifyPin(String attempt) async {
    final expected = await getPin();
    return attempt.trim() == expected;
  }
}
