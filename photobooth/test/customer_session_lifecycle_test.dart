import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/customer_session_lifecycle.dart';
import 'package:photobooth/services/fcm_payment_pending_store.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('endPhotoboothCustomerSession', () {
    test('clears persisted session between two synthetic customer flows',
        () async {
      SharedPreferences.setMockInitialValues({});

      final sm = SessionManager();

      sm.setSessionFromResponse({
        'id': 'session-a',
        'termsAccepted': true,
        'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'attemptsUsed': 0,
        'generatedImages': [],
        'expiresAt': DateTime.utc(2027, 1, 1).toIso8601String(),
      });
      expect(sm.sessionId, 'session-a');

      await endPhotoboothCustomerSession();
      expect(sm.hasSession, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('photobooth.session.current'), isNull);

      // Second "customer": new session, then tear down again.
      sm.setSessionFromResponse({
        'id': 'session-b',
        'termsAccepted': true,
        'termsAcceptedAt': DateTime.utc(2026, 1, 2).toIso8601String(),
        'attemptsUsed': 0,
        'generatedImages': [],
        'expiresAt': DateTime.utc(2027, 1, 2).toIso8601String(),
      });
      expect(sm.sessionId, 'session-b');

      await endPhotoboothCustomerSession();
      expect(sm.hasSession, isFalse);
      expect(prefs.getString('photobooth.session.current'), isNull);
    });

    test(
        'endCustomerSession removes stale prefs when memory was never restored',
        () async {
      SharedPreferences.setMockInitialValues({
        'photobooth.session.current':
            '{"id":"ghost","termsAccepted":true,"termsAcceptedAt":"2026-01-01T00:00:00.000Z","attemptsUsed":0,"generatedImages":[],"expiresAt":"2027-01-01T00:00:00.000Z"}',
      });

      // Singleton may have null memory (no restore()); disk still has JSON — e.g. after a partial crash.
      await SessionManager().endCustomerSession();
      expect(SessionManager().hasSession, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('photobooth.session.current'), isNull);
    });

    test('clears disk-persisted FCM pending payment payload', () async {
      SharedPreferences.setMockInitialValues({
        'photobooth.fcm.pending_payment_payload':
            '{"data":{"type":"PAYMENT_APPROVED","paymentId":"pay-x"},"originSessionId":"s-old"}',
      });

      await endPhotoboothCustomerSession();

      expect(await FcmPaymentPendingStore.takePending(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('photobooth.fcm.pending_payment_payload'), isNull);
    });
  });
}
