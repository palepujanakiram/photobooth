import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'fcm_token_store.dart';

/// Resolves the device FCM registration token when Firebase is initialized (native only).
///
/// Successful tokens are persisted ([FcmTokenStore]) for [FirebaseMessaging.onTokenRefresh] parity
/// and as a fallback when [FirebaseMessaging.getToken] returns null transiently.
class FcmService {
  FcmService._();

  /// Returns the FCM token, or null if unavailable (web, denied permission, or error).
  static Future<String?> getToken() async {
    if (kIsWeb) return null;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        if (kDebugMode) {
          debugPrint('FCM FcmService.getToken: permission denied');
        }
        return null;
      }
      final token = await messaging.getToken();
      if (token != null && token.trim().isNotEmpty) {
        await FcmTokenStore.save(token);
        return token;
      }
      final cached = await FcmTokenStore.getCached();
      if (cached != null && kDebugMode) {
        debugPrint(
          'FCM FcmService.getToken: Firebase returned empty; using cached token',
        );
      }
      return cached;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('FCM FcmService.getToken failed: $e\n$st');
      }
      return await FcmTokenStore.getCached();
    }
  }
}
