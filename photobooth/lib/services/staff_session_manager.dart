import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StaffSession {
  final String token;
  final Map<String, dynamic> staff;

  StaffSession({required this.token, required this.staff});
}

/// Persists staff session token (X-Staff-Token) and basic staff info.
class StaffSessionManager {
  static const String _kSecureStaffToken = 'staff_session_token';
  static const String _kPrefsStaffJson = 'staff_session_staff_json';

  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  Future<String?> getToken() async {
    final t = await _secure.read(key: _kSecureStaffToken);
    if (t == null) return null;
    final trimmed = t.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> setSession({
    required String token,
    required String staffJson,
  }) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      await clear();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    try {
      // Write metadata first; if token write fails, session remains effectively unusable.
      await prefs.setString(_kPrefsStaffJson, staffJson);
      await _secure.write(key: _kSecureStaffToken, value: trimmed);
    } catch (_) {
      // Avoid partial sessions (e.g. token without staffJson, or vice versa).
      await clear();
      rethrow;
    }
  }

  Future<String?> getStaffJson() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_kPrefsStaffJson);
    if (v == null) return null;
    final trimmed = v.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await _secure.delete(key: _kSecureStaffToken);
    await prefs.remove(_kPrefsStaffJson);
  }
}

