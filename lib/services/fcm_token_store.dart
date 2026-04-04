import 'package:shared_preferences/shared_preferences.dart';

/// Persists the FCM registration token for refresh handling ([FirebaseMessaging.onTokenRefresh])
/// and as a last resort when [FirebaseMessaging.getToken] is temporarily null.
class FcmTokenStore {
  FcmTokenStore._();

  static const _key = 'fcm_registration_token';

  static Future<void> save(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, trimmed);
  }

  /// Last token persisted from [save], [FcmService.getToken], or [onTokenRefresh].
  static Future<String?> getCached() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_key)?.trim();
    if (v == null || v.isEmpty) return null;
    return v;
  }
}
