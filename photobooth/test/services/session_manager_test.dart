import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SessionManager().clearSession();
  });

  test('setSessionFromResponse and getters', () {
    final sm = SessionManager();
    sm.setSessionFromResponse({
      'id': 'sess-9',
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'attemptsUsed': 2,
      'generatedImages': [],
      'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
      'kioskId': 'k1',
      'selectedThemeId': 't1',
    });
    expect(sm.currentSession?.sessionId, 'sess-9');
    expect(sm.currentSession?.selectedThemeId, 't1');
  });

  test('restore reloads session from SharedPreferences', () async {
    SessionManager().clearSession();
    final payload = {
      'id': 'sess-persist',
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': <dynamic>[],
      'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
    };
    SharedPreferences.setMockInitialValues({
      'photobooth.session.current': jsonEncode(payload),
    });
    final sm = SessionManager();
    await sm.restore();
    expect(sm.currentSession?.sessionId, 'sess-persist');
  });

  test('endCustomerSession clears persisted session', () async {
    SessionManager().setSessionFromResponse({
      'id': 'sess-end',
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': [],
      'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
    });
    await SessionManager().endCustomerSession();
    expect(SessionManager().hasSession, isFalse);
  });
}
