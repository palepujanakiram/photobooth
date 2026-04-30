import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';

/// Writes FCM payloads from [FirebaseMessaging.onBackgroundMessage] so the main
/// isolate can apply payment UI after resume.
///
/// Background handlers run in a **separate isolate**; coordinator callbacks
/// registered on the result screen exist only on the main isolate.
const String _prefsKey = 'photobooth.fcm.pending_payment_payload';

class FcmPaymentPendingStore {
  FcmPaymentPendingStore._();

  static Future<void> persist(RemoteMessage message) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = <String, dynamic>{
        'data': Map<String, dynamic>.from(message.data),
      };
      final n = message.notification;
      if (n != null) {
        payload['notification'] = <String, String?>{
          'title': n.title,
          'body': n.body,
        };
      }
      await prefs.setString(_prefsKey, jsonEncode(payload));
      if (kDebugMode) {
        AppLogger.debug(
          'FCM background: stored pending payload for main isolate '
          '(data keys: ${message.data.keys.toList()})',
        );
      }
    } catch (e, st) {
      if (kDebugMode) {
        AppLogger.debug('FCM background persist failed: $e\n$st');
      }
    }
  }

  /// Writes [pending] again when flush could not show UI (e.g. no [Navigator] yet).
  static Future<void> restore(Map<String, dynamic> pending) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(pending));
      if (kDebugMode) {
        AppLogger.debug('FCM: restored pending payment payload for retry');
      }
    } catch (e, st) {
      if (kDebugMode) {
        AppLogger.debug('FCM restore pending failed: $e\n$st');
      }
    }
  }

  /// Returns decoded entry and clears it, or null.
  static Future<Map<String, dynamic>?> takePending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return null;
      await prefs.remove(_prefsKey);
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (e, st) {
      if (kDebugMode) {
        AppLogger.debug('FCM takePending failed: $e\n$st');
      }
      return null;
    }
  }
}
