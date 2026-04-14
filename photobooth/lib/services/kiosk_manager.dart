import 'package:shared_preferences/shared_preferences.dart';

class KioskManager {
  static const String _kPrefsKioskCode = 'kiosk_code';

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
}

