import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

class KioskManager {
  static const String _kPrefsKioskCode = 'kiosk_code';
  static const String _kPrefsPaymentEnabledOverride = 'kiosk_payment_enabled_override';

  static bool? _cachedPaymentEnabledOverride;

  /// Clears in-memory payment override cache (tests only).
  @visibleForTesting
  static void resetPaymentOverrideCacheForTests() {
    _cachedPaymentEnabledOverride = null;
  }

  Future<String?> getKioskCode() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_kPrefsKioskCode);
    if (v == null) return null;
    final trimmed = v.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> setKioskCode(String? code) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = code?.trim() ?? '';
    if (trimmed.isEmpty) {
      await prefs.remove(_kPrefsKioskCode);
      return;
    }
    await prefs.setString(_kPrefsKioskCode, trimmed.toUpperCase());
  }

  Future<void> clearKioskCode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefsKioskCode);
  }

  /// Payment enablement override from `GET /api/kiosk/by-code/:code`.
  ///
  /// - null: inherit (default behavior; payments enabled)
  /// - true: force enabled
  /// - false: force disabled (kiosk must hide all pricing details + skip payment flow)
  Future<bool?> getPaymentEnabledOverride() async {
    if (_cachedPaymentEnabledOverride != null) {
      return _cachedPaymentEnabledOverride;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_kPrefsPaymentEnabledOverride)) {
      return null;
    }
    final v = prefs.getBool(_kPrefsPaymentEnabledOverride);
    _cachedPaymentEnabledOverride = v;
    return v;
  }

  Future<void> setPaymentEnabledOverride(bool? value) async {
    _cachedPaymentEnabledOverride = value;
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_kPrefsPaymentEnabledOverride);
      return;
    }
    await prefs.setBool(_kPrefsPaymentEnabledOverride, value);
  }

  Future<void> clearPaymentEnabledOverride() async {
    _cachedPaymentEnabledOverride = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefsPaymentEnabledOverride);
  }
}

