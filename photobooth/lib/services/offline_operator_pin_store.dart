import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

/// Booth operator PINs for offline cash confirm on the Pay screen.
///
/// Accepted PINs (any match works):
/// - [masterPin] (`2468`) — always
/// - Server pins from `/api/settings` → `offlineCashPins` (staff configured in admin)
/// - Optional local override set from the staff dashboard
class OfflineOperatorPinStore {
  OfflineOperatorPinStore._();

  /// Unused in production; exists so unit tests can construct the store.
  @visibleForTesting
  static OfflineOperatorPinStore createForTests() =>
      OfflineOperatorPinStore._();

  static const prefsKeyLocal = 'kiosk_offline_operator_pin';
  static const prefsKeyServer = 'kiosk_offline_cash_pins';

  /// Factory / master key — always accepted even when staff pins are configured.
  static const masterPin = '2468';

  /// @deprecated Use [masterPin]; kept for older call sites / tests.
  static const defaultPin = masterPin;

  static Set<String>? _cachedAccepted;

  @visibleForTesting
  static void resetCacheForTests() {
    _cachedAccepted = null;
  }

  static bool isValidPinFormat(String pin) {
    final t = pin.trim();
    return RegExp(r'^\d{4,8}$').hasMatch(t);
  }

  /// Replace cached server pins (from settings fetch / disk hydrate).
  static Future<void> syncServerPins(Iterable<String>? pins) async {
    final normalized = _normalizePinList(pins);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKeyServer, jsonEncode(normalized));
    _cachedAccepted = null;
  }

  /// Local override used on this kiosk (staff dashboard). Does not remove
  /// [masterPin] or server pins from verification.
  static Future<void> setPin(String pin) async {
    final next = pin.trim();
    if (!isValidPinFormat(next)) {
      throw ArgumentError('PIN must be 4–8 digits');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKeyLocal, next);
    _cachedAccepted = null;
  }

  static Future<bool> verifyPin(String attempt) async {
    final a = attempt.trim();
    if (a.isEmpty) return false;
    final accepted = await _acceptedPins();
    return accepted.contains(a);
  }

  static Future<Set<String>> _acceptedPins() async {
    final cached = _cachedAccepted;
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    final out = <String>{masterPin};

    final serverRaw = prefs.getString(prefsKeyServer);
    if (serverRaw != null && serverRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(serverRaw);
        out.addAll(_normalizePinList(decoded is List ? decoded : null));
      } catch (_) {
        // Ignore corrupt cache; master + local still work.
      }
    }

    final local = prefs.getString(prefsKeyLocal)?.trim() ?? '';
    if (isValidPinFormat(local)) {
      out.add(local);
    }

    _cachedAccepted = out;
    return out;
  }

  static List<String> _normalizePinList(Iterable<dynamic>? pins) {
    if (pins == null) return const [];
    final out = <String>{};
    for (final raw in pins) {
      final p = raw?.toString().trim() ?? '';
      if (isValidPinFormat(p)) out.add(p);
    }
    return out.toList()..sort();
  }
}
