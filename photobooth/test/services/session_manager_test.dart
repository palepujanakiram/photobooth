import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:photobooth/services/local_kiosk_store.dart';
import 'package:photobooth/utils/print_orientation.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    LocalKioskStore.resetInstance();
    SharedPreferences.setMockInitialValues({});
    await SessionManager().endCustomerSession();
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

  test('setPersonCount syncs landscape print orientation for groups', () {
    final sm = SessionManager();
    sm.setSessionFromResponse({
      'id': 'sess-pc',
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': [],
      'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
    });
    sm.setPersonCount(4);
    expect(sm.personCount, 4);
    expect(sm.printOrientation, PrintOrientation.landscape);
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

  test('isOfflineSession follows session offline flag', () {
    final sm = SessionManager();
    sm.setSessionFromResponse({
      'id': 'sess-on',
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': [],
      'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
    });
    expect(sm.isOfflineSession, isFalse);
    sm.setSessionFromResponse({
      'id': 'sess-off',
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': [],
      'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
      'offline': true,
    });
    expect(sm.isOfflineSession, isTrue);
  });

  test('share token round-trips and is minted only once', () async {
    final sm = SessionManager();
    sm.setSessionFromResponse({
      'id': 'sess-share',
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': [],
      'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
      'offline': true,
    });

    final first = await sm.ensureShareToken();
    final second = await sm.ensureShareToken();

    expect(first, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(second, first);
    expect(sm.currentSession?.toJson()['shareToken'], first);
  });

  test('session responses preserve an existing share token', () {
    final sm = SessionManager();
    final base = {
      'id': 'sess-preserve-share',
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': <dynamic>[],
      'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
    };
    sm.setSessionFromResponse({...base, 'shareToken': 'stable-token'});
    sm.setSessionFromResponse({...base, 'attemptsUsed': 1});

    expect(sm.shareToken, 'stable-token');
  });
}
