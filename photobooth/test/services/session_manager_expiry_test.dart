import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    SessionManager().clearSession();
  });

  test('currentSession stays valid until grace after expiresAt', () {
    final sm = SessionManager();
    sm.setSessionFromResponse({
      'id': 'sess-expiry',
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.now().toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': [],
      'expiresAt': DateTime.now()
          .add(const Duration(minutes: 3))
          .toIso8601String(),
    });

    expect(sm.hasSession, isTrue);
    expect(sm.isSessionExpired, isFalse);
  });

  test('currentSession null after expiresAt plus grace', () {
    final sm = SessionManager();
    final past = DateTime.now().subtract(const Duration(minutes: 6));
    sm.setSessionFromResponse({
      'id': 'sess-expiry',
      'termsAccepted': true,
      'termsAcceptedAt': past.toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': [],
      'expiresAt': past.toIso8601String(),
    });

    expect(sm.currentSession, isNull);
    expect(sm.isSessionExpired, isTrue);
  });

  test('session valid inside grace window after expiry', () {
    final sm = SessionManager();
    final expiredRecently = DateTime.now().subtract(const Duration(minutes: 2));
    sm.setSessionFromResponse({
      'id': 'sess-grace',
      'termsAccepted': true,
      'termsAcceptedAt': expiredRecently.toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': [],
      'expiresAt': expiredRecently.toIso8601String(),
    });

    expect(sm.currentSession, isNotNull);
    expect(sm.isSessionExpired, isFalse);
  });
}
