import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../utils/logger.dart';

class WhatsAppStatusPayload {
  WhatsAppStatusPayload({
    required this.sessionId,
    required this.status,
    this.deliveredAt,
    this.readAt,
    this.error,
    this.messageId,
  });

  final String sessionId;
  final String status;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final String? error;
  final String? messageId;

  static String? _emptyToNull(String? s) {
    final t = s?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  static DateTime? _parseIso(String? s) {
    final t = _emptyToNull(s);
    if (t == null) return null;
    return DateTime.tryParse(t);
  }

  factory WhatsAppStatusPayload.fromRemoteMessage(RemoteMessage m) {
    final d = Map<String, dynamic>.from(m.data);
    return WhatsAppStatusPayload(
      sessionId: (d['sessionId'] ?? '').toString(),
      status: (d['status'] ?? '').toString(),
      deliveredAt: _parseIso(d['deliveredAt']?.toString()),
      readAt: _parseIso(d['readAt']?.toString()),
      error: _emptyToNull(d['error']?.toString()),
      messageId: _emptyToNull(d['messageId']?.toString()),
    );
  }

  bool get isValid => sessionId.trim().isNotEmpty && status.trim().isNotEmpty;
}

typedef WhatsAppStatusCallback = void Function(WhatsAppStatusPayload payload);

/// Silent WhatsApp delivery status pushes (`data.type == WHATSAPP_STATUS`).
class WhatsAppPushCoordinator {
  WhatsAppPushCoordinator._();
  static final WhatsAppPushCoordinator instance = WhatsAppPushCoordinator._();

  static const String typeWhatsAppStatus = 'WHATSAPP_STATUS';

  WhatsAppStatusCallback? _callback;

  void registerCallback(WhatsAppStatusCallback? cb) {
    _callback = cb;
  }

  bool handleRemoteMessage(RemoteMessage message) {
    final type = (message.data['type'] ?? '').toString();
    if (type != typeWhatsAppStatus) return false;

    final payload = WhatsAppStatusPayload.fromRemoteMessage(message);
    if (!payload.isValid) {
      if (kDebugMode) {
        AppLogger.debug('FCM WHATSAPP_STATUS ignored (invalid payload): ${message.data}');
      }
      return true;
    }

    if (kDebugMode) {
      AppLogger.debug(
        'FCM WHATSAPP_STATUS session=${payload.sessionId} status=${payload.status}',
      );
    }

    _callback?.call(payload);
    return true;
  }
}
