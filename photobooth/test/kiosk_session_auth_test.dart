import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/kiosk_session_auth.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('requestNeedsKioskSessionToken', () {
    test('requires token for session sub-routes except accept-terms', () {
      expect(requestNeedsKioskSessionToken('/api/sessions/accept-terms'), isFalse);
      expect(
        requestNeedsKioskSessionToken('/api/sessions/abc-123'),
        isTrue,
      );
      expect(
        requestNeedsKioskSessionToken('/api/sessions/abc-123/fcm-token'),
        isTrue,
      );
    });

    test('requires token for generation, payment, preprocess', () {
      expect(requestNeedsKioskSessionToken('/api/preprocess-image'), isTrue);
      expect(requestNeedsKioskSessionToken('/api/generate-image'), isTrue);
      expect(
        requestNeedsKioskSessionToken('/api/generate-stream-parallel'),
        isTrue,
      );
      expect(
        requestNeedsKioskSessionToken('/api/generation-runs/run-1'),
        isTrue,
      );
      expect(requestNeedsKioskSessionToken('/api/payment/initiate'), isTrue);
      expect(
        requestNeedsKioskSessionToken('/api/payments/status/pay-1'),
        isTrue,
      );
    });

    test('does not require token for themes or session create', () {
      expect(requestNeedsKioskSessionToken('/api/themes'), isFalse);
      expect(requestNeedsKioskSessionToken('/api/settings'), isFalse);
    });
  });

  group('KioskSessionTokenInterceptor', () {
    test('adds X-Kiosk-Session-Token on PATCH session', () async {
      SharedPreferences.setMockInitialValues({});
      final sm = SessionManager();
      sm.setSessionFromResponse({
        'id': 'sess-1',
        'kioskAuthToken': 'secret-token',
        'termsAccepted': true,
        'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'attemptsUsed': 0,
        'generatedImages': [],
        'expiresAt': DateTime.utc(2027, 1, 1).toIso8601String(),
      });

      final dio = Dio();
      dio.interceptors.add(KioskSessionTokenInterceptor(sessionManager: sm));
      dio.httpClientAdapter = _CapturingAdapter();

      await dio.patch<void>('/api/sessions/sess-1');

      final adapter = dio.httpClientAdapter as _CapturingAdapter;
      expect(
        adapter.lastHeaders?[kKioskSessionTokenHeader],
        'secret-token',
      );
    });
  });

  group('parseKioskAuthToken / setSessionFromResponse', () {
    test('preserves token when PATCH omits kioskAuthToken', () {
      SharedPreferences.setMockInitialValues({});
      final sm = SessionManager();
      sm.setSessionFromResponse({
        'id': 'sess-1',
        'kioskAuthToken': 'keep-me',
        'termsAccepted': true,
        'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'attemptsUsed': 0,
        'generatedImages': [],
        'expiresAt': DateTime.utc(2027, 1, 1).toIso8601String(),
      });

      sm.setSessionFromResponse({
        'id': 'sess-1',
        'termsAccepted': true,
        'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'attemptsUsed': 1,
        'generatedImages': [],
        'expiresAt': DateTime.utc(2027, 1, 1).toIso8601String(),
        'selectedThemeId': 'theme-a',
      });

      expect(sm.kioskAuthToken, 'keep-me');
    });

    test('accepts alternate token keys', () {
      SharedPreferences.setMockInitialValues({});
      final sm = SessionManager();
      sm.setSessionFromResponse({
        'id': 'sess-2',
        'kioskSessionToken': 'alt-token',
        'termsAccepted': true,
        'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'attemptsUsed': 0,
        'generatedImages': [],
        'expiresAt': DateTime.utc(2027, 1, 1).toIso8601String(),
      });
      expect(sm.kioskAuthToken, 'alt-token');
    });
  });
}

class _CapturingAdapter implements HttpClientAdapter {
  Map<String, dynamic>? lastHeaders;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastHeaders = Map<String, dynamic>.from(options.headers);
    return ResponseBody.fromString('{}', 200);
  }
}
