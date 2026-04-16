import 'package:shared_preferences/shared_preferences.dart';

class StaffSession {
  final String token;
  final Map<String, dynamic> staff;

  StaffSession({required this.token, required this.staff});
}

/// Persists staff session token (X-Staff-Token) and basic staff info.
class StaffSessionManager {
  static const String _kPrefsStaffToken = 'staff_session_token';
  static const String _kPrefsStaffJson = 'staff_session_staff_json';

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString(_kPrefsStaffToken);
    if (t == null) return null;
    final trimmed = t.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> setSession({
    required String token,
    required String staffJson,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      await clear();
      return;
    }
    await prefs.setString(_kPrefsStaffToken, trimmed);
    await prefs.setString(_kPrefsStaffJson, staffJson);
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
    await prefs.remove(_kPrefsStaffToken);
    await prefs.remove(_kPrefsStaffJson);
  }
}

