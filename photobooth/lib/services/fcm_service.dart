import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'fcm_token_store.dart';
import '../utils/logger.dart';

/// Resolves the device FCM registration token when Firebase is initialized (native only).
///
/// Successful tokens are persisted ([FcmTokenStore]) for [FirebaseMessaging.onTokenRefresh] parity
/// and as a fallback when [FirebaseMessaging.getToken] returns null transiently.
class FcmService {
  FcmService._();

  static bool _startupPermissionRequested = false;

  /// Requests notification permission (once) and caches the FCM token.
  ///
  /// On Android kiosks this is deferred until Terms so it does not compete
  /// with the Canon USB allow dialog on cold start.
  static Future<void> ensurePermissionAndPersistToken() async {
    if (kIsWeb || _startupPermissionRequested) return;
    _startupPermissionRequested = true;
    try {
      final messaging = FirebaseMessaging.instance;
      final perm = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      if (kDebugMode) {
        AppLogger.debug('FCM permission: ${perm.authorizationStatus}');
      }

      final token = await messaging.getToken();
      if (token != null && token.trim().isNotEmpty) {
        await FcmTokenStore.save(token);
      }
      if (kDebugMode) {
        AppLogger.debug(
          token != null
              ? 'FCM registration token (use in payment init & server): $token'
              : 'FCM registration token: null',
        );
      }

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await messaging.setForegroundNotificationPresentationOptions(
          alert: false,
          badge: false,
          sound: false,
        );
      }
    } catch (e, st) {
      AppLogger.error('FCM ensurePermission failed: $e', error: e, stackTrace: st);
    }
  }

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
          AppLogger.debug('FCM getToken: permission denied');
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
        AppLogger.debug('FCM getToken: Firebase returned empty; using cached token');
      }
      return cached;
    } catch (e, st) {
      // Error path should be visible in release logs too.
      AppLogger.error('FCM getToken failed: $e', error: e, stackTrace: st);
      return await FcmTokenStore.getCached();
    }
  }
}
