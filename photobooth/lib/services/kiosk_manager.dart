import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

class KioskManager {
  static const String _kPrefsKioskCode = 'kiosk_code';
  static const String _kPrefsPaymentEnabledOverride =
      'kiosk_payment_enabled_override';
  static const String _kPrefsClassicPhotosEnabled =
      'kiosk_classic_photos_enabled';
  static const String _kPrefsOperatingModeOffline =
      'kiosk_operating_mode_offline';

  static bool? _cachedPaymentEnabledOverride;
  static bool? _cachedClassicPhotosEnabled;
  static bool? _cachedOperatingModeOffline;

  /// Clears in-memory payment override cache (tests only).
  @visibleForTesting
  static void resetPaymentOverrideCacheForTests() {
    _cachedPaymentEnabledOverride = null;
  }

  /// Clears in-memory Classic photos cache (tests only).
  @visibleForTesting
  static void resetClassicPhotosCacheForTests() {
    _cachedClassicPhotosEnabled = null;
  }

  /// Clears in-memory operating-mode cache (tests only).
  @visibleForTesting
  static void resetOperatingModeCacheForTests() {
    _cachedOperatingModeOffline = null;
  }

  /// Sync snapshot of admin offline mode (splash / terms refresh).
  static bool get isOperatingModeOfflineCached =>
      _cachedOperatingModeOffline == true;

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

  /// Whether Classic (4-shot strip) is offered after terms.
  ///
  /// Defaults to **true** when unset (older binds / missing API field).
  Future<bool> isClassicPhotosEnabled() async {
    final cached = _cachedClassicPhotosEnabled;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_kPrefsClassicPhotosEnabled)) {
      return true;
    }
    final v = prefs.getBool(_kPrefsClassicPhotosEnabled) ?? true;
    _cachedClassicPhotosEnabled = v;
    return v;
  }

  Future<void> setClassicPhotosEnabled(bool enabled) async {
    _cachedClassicPhotosEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrefsClassicPhotosEnabled, enabled);
  }

  Future<void> clearClassicPhotosEnabled() async {
    _cachedClassicPhotosEnabled = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefsClassicPhotosEnabled);
  }

  /// Admin **Offline** guest mode — frame-only + cash even when WAN is up.
  ///
  /// Defaults to **false** (online) when unset.
  Future<bool> isOperatingModeOffline() async {
    final cached = _cachedOperatingModeOffline;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_kPrefsOperatingModeOffline)) {
      return false;
    }
    final v = prefs.getBool(_kPrefsOperatingModeOffline) ?? false;
    _cachedOperatingModeOffline = v;
    return v;
  }

  Future<void> setOperatingModeOffline(bool offline) async {
    _cachedOperatingModeOffline = offline;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrefsOperatingModeOffline, offline);
  }

  Future<void> clearOperatingModeOffline() async {
    _cachedOperatingModeOffline = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefsOperatingModeOffline);
  }
}
