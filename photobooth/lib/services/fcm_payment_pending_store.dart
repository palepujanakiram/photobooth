import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';
import 'error_reporting/error_reporting_manager.dart';

/// Writes FCM payloads from [FirebaseMessaging.onBackgroundMessage] so the main
/// isolate can apply payment UI after resume.
///
/// Background handlers run in a **separate isolate**; coordinator callbacks
/// registered on the result screen exist only on the main isolate.
const String _prefsKey = 'photobooth.fcm.pending_payment_payload';

class FcmPaymentPendingStore {
  FcmPaymentPendingStore._();

  static String? _extractSessionId(Map<String, dynamic> data) {
    final raw = (data['sessionId'] ?? data['session_id'])?.toString();
    if (raw == null) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static Future<void> persist(RemoteMessage message) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = <String, dynamic>{
        'data': Map<String, dynamic>.from(message.data),
        // Snapshot the originating sessionId from the payload so we can detect
        // cross-session contamination after app restarts / kiosk wipes.
        'originSessionId': _extractSessionId(message.data),
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
        AppLogger.error('FCM background persist failed: $e', error: e, stackTrace: st);
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
        AppLogger.error('FCM restore pending failed: $e', error: e, stackTrace: st);
      }
    }
  }

  /// Returns decoded entry and clears it, or null.
  static Future<Map<String, dynamic>?> takePending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        await prefs.remove(_prefsKey);
        return decoded;
      }
      if (decoded is Map) {
        await prefs.remove(_prefsKey);
        return Map<String, dynamic>.from(decoded);
      }
      // Successfully decoded but unexpected shape; discard to avoid retry loops.
      await prefs.remove(_prefsKey);
      return null;
    } catch (e, st) {
      // Corrupt payload — discard so we don't loop on every flush/resume.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefsKey);
      } catch (_) {
        // Best-effort
      }
      if (kDebugMode) {
        AppLogger.error('FCM takePending failed (discarded): $e', error: e, stackTrace: st);
      }
      await ErrorReportingManager.recordError(
        e,
        st,
        reason: 'FCM pending payload corrupt',
        fatal: false,
      );
      return null;
    }
  }
}
