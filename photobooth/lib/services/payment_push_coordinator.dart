import 'dart:convert';
import 'dart:developer' as developer;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'fcm_payment_pending_store.dart';
import 'error_reporting/error_reporting_manager.dart';
import 'whatsapp_push_coordinator.dart';
import '../utils/logger.dart';
import 'session_manager.dart';

/// Payload from FCM `data` + optional `notification` for payment updates.
///
/// Supported Cashfree webhook → FCM shape (both blocks together):
/// ```json
/// {
///   "notification": {
///     "title": "Payment Confirmed ✓",
///     "body": "₹250 paid successfully. Proceed to print your photo."
///   },
///   "data": {
///     "type": "PAYMENT_APPROVED",
///     "paymentId": "payment-uuid",
///     "amount": "250"
///   }
/// }
/// ```
/// FCM requires every `data` value to be a **string** (not a JSON number). Once this
/// message reaches the device, [fromRemoteMessage] maps it to [isApproved] / print flow.
class PaymentPushPayload {
  PaymentPushPayload({
    required this.type,
    this.paymentId,
    this.amount,
    this.title,
    this.body,
  });

  final String type;
  final String? paymentId;
  final String? amount;
  final String? title;
  final String? body;

  bool get isApproved => type == PaymentPushCoordinator.typeApproved;

  bool get isFailed =>
      type == PaymentPushCoordinator.typeFailed ||
      type == PaymentPushCoordinator.typeDeclined ||
      type == PaymentPushCoordinator.typeRejected;

  /// Parses FCM payloads. Backends vary: `type`, `status`, nested JSON, or notification-only.
  factory PaymentPushPayload.fromRemoteMessage(RemoteMessage m) {
    return PaymentPushPayload.fromFcmData(
      Map<String, dynamic>.from(m.data),
      notificationTitle: m.notification?.title,
      notificationBody: m.notification?.body,
    );
  }

  /// Same parsing as [fromRemoteMessage], for payloads restored from storage.
  factory PaymentPushPayload.fromFcmData(
    Map<String, dynamic> data, {
    String? notificationTitle,
    String? notificationBody,
  }) {
    final flat = _flattenFcmData(data);
    if (kDebugMode) {
      AppLogger.debug('FCM flat data: $flat');
    }

    var type = _resolveTypeFromFields(flat);
    if (type.isEmpty) {
      type = _inferTypeFromNotificationText(notificationTitle, notificationBody);
    }

    return PaymentPushPayload(
      type: type,
      paymentId: _firstNonEmptyOptional(flat, const [
        'paymentId',
        'payment_id',
        'id',
        'paymentIntentId',
        'payment_intent_id',
        'orderId',
        'order_id',
      ]),
      amount: _firstNonEmptyOptional(flat, const ['amount', 'price', 'value']),
      title: notificationTitle,
      body: notificationBody,
    );
  }

  static String? _firstNonEmptyOptional(
    Map<String, String> flat,
    List<String> keys,
  ) {
    for (final k in keys) {
      final v = flat[k]?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  /// Merge FCM data entries and unwrap JSON blobs some servers put in a single key.
  static Map<String, String> _flattenFcmData(Map<String, dynamic> raw) {
    final flat = <String, String>{};

    void put(String k, String v) {
      final key = k.trim();
      if (key.isEmpty) return;
      flat[key] = v.trim();
    }

    for (final e in raw.entries) {
      put(e.key, e.value?.toString() ?? '');
    }

    for (final key in List<String>.from(flat.keys)) {
      final v = flat[key] ?? '';
      final t = v.trim();
      if (t.startsWith('{') && t.endsWith('}')) {
        try {
          final decoded = jsonDecode(t);
          if (decoded is Map<String, dynamic>) {
            decoded.forEach((k, val) {
              put(k.toString(), val?.toString() ?? '');
            });
          }
        } catch (_) {}
      }
    }

    return flat;
  }

  static String _normalizeToken(String raw) {
    return raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '_');
  }

  static String _resolveTypeFromFields(Map<String, String> flat) {
    const typeKeys = [
      'type',
      'eventType',
      'event_type',
      'event',
      'action',
      'paymentEvent',
      'payment_event',
      'payment_type',
      'paymentType',
    ];

    for (final k in typeKeys) {
      final v = flat[k];
      if (v != null && v.isNotEmpty) {
        final n = _normalizeToken(v);
        final mapped = _mapTypeAlias(n);
        if (mapped.isNotEmpty) return mapped;
      }
    }

    const statusKeys = ['status', 'paymentStatus', 'payment_status', 'state'];
    for (final k in statusKeys) {
      final v = flat[k];
      if (v == null || v.isEmpty) continue;
      final n = _normalizeToken(v);
      if (_statusMeansApproved(n)) return PaymentPushCoordinator.typeApproved;
      if (_statusMeansFailed(n)) return PaymentPushCoordinator.typeFailed;
    }

    return '';
  }

  static bool _statusMeansApproved(String n) {
    return n == 'APPROVED' ||
        n == 'SUCCESS' ||
        n == 'SUCCEEDED' ||
        n == 'PAID' ||
        n == 'COMPLETED' ||
        n == 'COMPLETE' ||
        n == 'CAPTURED' ||
        n == 'CONFIRMED';
  }

  static bool _statusMeansFailed(String n) {
    return n == 'FAILED' ||
        n == 'FAILURE' ||
        n == 'DECLINED' ||
        n == 'REJECTED' ||
        n == 'CANCELLED' ||
        n == 'CANCELED';
  }

  /// Maps common aliases to canonical payment types.
  static String _mapTypeAlias(String n) {
    if (n == PaymentPushCoordinator.typeApproved ||
        n == 'APPROVED' ||
        n == 'PAYMENT_SUCCESS' ||
        n == 'SUCCESS' ||
        n == 'PAID') {
      return PaymentPushCoordinator.typeApproved;
    }
    if (n == PaymentPushCoordinator.typeFailed ||
        n == 'FAILED' ||
        n == 'FAILURE') {
      return PaymentPushCoordinator.typeFailed;
    }
    if (n == PaymentPushCoordinator.typeDeclined || n == 'DECLINED') {
      return PaymentPushCoordinator.typeDeclined;
    }
    if (n == PaymentPushCoordinator.typeRejected || n == 'REJECTED') {
      return PaymentPushCoordinator.typeRejected;
    }
    if (n.contains('APPROVED') && n.contains('PAYMENT')) {
      return PaymentPushCoordinator.typeApproved;
    }
    if (n.contains('FAILED') && n.contains('PAYMENT')) {
      return PaymentPushCoordinator.typeFailed;
    }
    return n;
  }

  static String _inferTypeFromNotificationText(
    String? notificationTitle,
    String? notificationBody,
  ) {
    final title = notificationTitle?.toLowerCase() ?? '';
    final body = notificationBody?.toLowerCase() ?? '';
    final combined = '$title $body';
    if (combined.isEmpty) return '';

    final looksPayment =
        combined.contains('payment') || combined.contains('paid');
    if (!looksPayment) return '';

    if (combined.contains('confirm') ||
        combined.contains('success') ||
        combined.contains('paid successfully') ||
        title.contains('✓')) {
      return PaymentPushCoordinator.typeApproved;
    }
    if (combined.contains('fail') ||
        combined.contains('declin') ||
        combined.contains('reject') ||
        combined.contains('could not')) {
      return PaymentPushCoordinator.typeFailed;
    }
    return '';
  }
}

typedef PaymentPushCallback = void Function(PaymentPushPayload payload);

/// Routes payment FCM messages to the [ResultScreen] when registered, otherwise shows a root dialog.
class PaymentPushCoordinator {
  PaymentPushCoordinator._();
  static final PaymentPushCoordinator instance = PaymentPushCoordinator._();

  static const String typeApproved = 'PAYMENT_APPROVED';
  static const String typeFailed = 'PAYMENT_FAILED';
  static const String typeDeclined = 'PAYMENT_DECLINED';
  static const String typeRejected = 'PAYMENT_REJECTED';

  GlobalKey<NavigatorState>? _navigatorKey;
  PaymentPushCallback? _resultScreenCallback;
  String? _lastHandledPaymentId;
  PaymentPushPayload? _queuedPaymentPayload;
  List<String>? _queuedPaymentDataKeys;

  void attachNavigator(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
    _drainQueuedPayment();
  }

  /// Set when [ResultScreen] is visible; cleared on dispose.
  void registerResultScreenCallback(PaymentPushCallback? callback) {
    _resultScreenCallback = callback;
    // Allow the Pay & Collect screen to receive the next push even if an earlier
    // flush handled the same paymentId without UI (navigator not ready), or startup
    // consumed state incorrectly.
    if (callback != null) {
      _lastHandledPaymentId = null;
      _drainQueuedPayment();
    }
  }

  /// Queue a message for later delivery when UI is ready.
  ///
  /// Used for cold-start `getInitialMessage()` so the payload isn't dispatched to
  /// the wrong screen while navigation is still settling.
  void queueRemoteMessage(RemoteMessage message) {
    final payload = PaymentPushPayload.fromRemoteMessage(message);
    if (!_isPaymentPayload(payload)) return;
    _queuedPaymentPayload = payload;
    _queuedPaymentDataKeys = message.data.keys.toList();
    _drainQueuedPayment();
  }

  void _drainQueuedPayment() {
    final p = _queuedPaymentPayload;
    if (p == null) return;
    final applied = dispatchParsedPayload(
      p,
      dataKeys: _queuedPaymentDataKeys,
    );
    if (applied) {
      _queuedPaymentPayload = null;
      _queuedPaymentDataKeys = null;
    }
  }

  bool _isPaymentPayload(PaymentPushPayload p) {
    return p.isApproved || p.isFailed;
  }

  void handleRemoteMessage(RemoteMessage message) {
    if (WhatsAppPushCoordinator.instance.handleRemoteMessage(message)) {
      return;
    }

    developer.log(
      'handleRemoteMessage id=${message.messageId} dataKeys=${message.data.keys.toList()} '
      'title=${message.notification?.title}',
      name: 'fotozen.fcm',
    );
    if (kDebugMode) {
      AppLogger.debug(
        'FCM rx messageId=${message.messageId} '
        'collapse=${message.collapseKey} data=${message.data} '
        'title=${message.notification?.title}',
      );
    }

    final payload = PaymentPushPayload.fromRemoteMessage(message);
    dispatchParsedPayload(payload, dataKeys: message.data.keys.toList());
  }

  /// Delivers a payload parsed from storage after [FirebaseMessaging.onBackgroundMessage].
  Future<void> flushPendingStoragePayment() async {
    final pending = await FcmPaymentPendingStore.takePending();
    if (pending == null) return;

    final dataRaw = pending['data'];
    if (dataRaw is! Map) return;
    final data = Map<String, dynamic>.from(dataRaw);

    // If we persisted an origin sessionId, verify it matches the currently restored session.
    // When originSessionId is absent (older payloads / backend doesn't send session id), keep legacy behavior.
    final originSessionId = pending['originSessionId']?.toString().trim();
    final currentSessionId = SessionManager().sessionId?.trim();
    if (originSessionId != null &&
        originSessionId.isNotEmpty &&
        currentSessionId != null &&
        currentSessionId.isNotEmpty &&
        originSessionId != currentSessionId) {
      developer.log(
        'flush dropped pending: session mismatch origin=$originSessionId current=$currentSessionId',
        name: 'fotozen.fcm',
      );
      if (kDebugMode) {
        AppLogger.debug(
          'FCM flush: dropped pending payload due to session mismatch '
          '(origin=$originSessionId current=$currentSessionId)',
        );
      }
      await ErrorReportingManager.recordError(
        Exception('Cross-session FCM payload dropped'),
        StackTrace.current,
        reason: 'FCM pending payload origin sessionId does not match current',
        extraInfo: {
          'originSessionId': originSessionId,
          'currentSessionId': currentSessionId,
        },
        fatal: false,
      );
      return;
    }
    String? title;
    String? body;
    final notif = pending['notification'];
    if (notif is Map) {
      title = notif['title']?.toString();
      body = notif['body']?.toString();
    }

    if (kDebugMode) {
      AppLogger.debug(
        'FCM flush pending from storage keys=${data.keys.toList()} '
        'title=$title',
      );
    }

    final payload = PaymentPushPayload.fromFcmData(
      data,
      notificationTitle: title,
      notificationBody: body,
    );
    if (!_isPaymentPayload(payload)) {
      developer.log(
        'flush dropped pending: type="${payload.type}" title="${payload.title}" '
        'body="${payload.body}" dataKeys=${data.keys.toList()}',
        name: 'fotozen.fcm',
      );
      if (kDebugMode) {
        AppLogger.debug(
          'FCM flush: stored pending is not a payment payload; see fotozen.fcm log',
        );
      }
      return;
    }

    final applied = dispatchParsedPayload(
      payload,
      dataKeys: data.keys.toList(),
    );
    if (!applied) {
      await FcmPaymentPendingStore.restore(pending);
    }
  }

  /// Returns whether payment UI was applied (callback invoked or dialog shown).
  bool dispatchParsedPayload(
    PaymentPushPayload payload, {
    List<String>? dataKeys,
  }) {
    if (!_isPaymentPayload(payload)) {
      if (kDebugMode) {
        AppLogger.debug(
          'FCM: push arrived but not handled as payment — type="${payload.type}" '
          'title="${payload.title}" body="${payload.body}" dataKeys=${dataKeys ?? []}. '
          'Add `type`/`status` in `data`, or notification text mentioning payment success/fail.',
        );
      }
      return false;
    }

    final id = payload.paymentId;
    if (id != null && id.isNotEmpty && id == _lastHandledPaymentId) {
      AppLogger.debug('FCM: duplicate paymentId ignored: $id');
      return true;
    }

    if (kDebugMode) {
      AppLogger.debug(
        'FCM payment → type=${payload.type} paymentId=${payload.paymentId} '
        'callback=${_resultScreenCallback != null}',
      );
    }

    if (_resultScreenCallback != null) {
      _resultScreenCallback!(payload);
      if (id != null && id.isNotEmpty) {
        _lastHandledPaymentId = id;
      }
      return true;
    }

    final ctx = _navigatorKey?.currentContext;
    if (ctx == null || !ctx.mounted) {
      AppLogger.debug(
        'FCM: no navigator context for payment dialog — will retry when ready',
      );
      return false;
    }

    _showGlobalPaymentDialog(payload, ctx);
    if (id != null && id.isNotEmpty) {
      _lastHandledPaymentId = id;
    }
    return true;
  }

  void _showGlobalPaymentDialog(PaymentPushPayload payload, BuildContext ctx) {
    final title = payload.title ??
        (payload.isApproved ? 'Payment confirmed' : 'Payment issue');
    final body = payload.body ??
        (payload.isApproved
            ? 'Your payment was approved. Open the payment screen to print.'
            : 'Your payment could not be completed.');

    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}
