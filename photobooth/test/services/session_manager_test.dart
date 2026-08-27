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

  test('attachDeliverableImageUrls writes proxy URLs and preserves them',
      () async {
    final sm = SessionManager();
    sm.setSessionFromResponse({
      'id': 'sess-thumbs',
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': <dynamic>[],
      'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
      'offline': true,
    });

    await sm.attachDeliverableImageUrls(
      imageUrls: const [
        'data:image/jpeg;base64,xx',
        '/api/img/fotoflashback/sheet.jpg',
      ],
      stripCompositeUrl: '/api/img/fotoflashback/sheet.jpg',
    );

    final session = sm.currentSession!;
    expect(session.generatedImages, ['/api/img/fotoflashback/sheet.jpg']);
    expect(session.latestImageUrl, '/api/img/fotoflashback/sheet.jpg');
    expect(session.stripCompositeUrl, '/api/img/fotoflashback/sheet.jpg');

    sm.setSessionFromResponse({
      'id': 'sess-thumbs',
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'attemptsUsed': 1,
      'generatedImages': <dynamic>[],
      'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
    });
    expect(
      sm.currentSession?.generatedImages,
      ['/api/img/fotoflashback/sheet.jpg'],
    );
    expect(
      sm.currentSession?.latestImageUrl,
      '/api/img/fotoflashback/sheet.jpg',
    );
  });

  test('attachDeliverableImageUrls accepts strip-only and no-ops safely',
      () async {
    final sm = SessionManager();
    await sm.attachDeliverableImageUrls(imageUrls: const ['/api/img/x.jpg']);
    expect(sm.currentSession, isNull);

    sm.setSessionFromResponse({
      'id': 'sess-strip-only',
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': <dynamic>[],
      'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
    });
    await sm.attachDeliverableImageUrls(
      imageUrls: const ['https://cdn.example/x.jpg'],
      stripCompositeUrl: '/api/img/fotoflashback/only-strip.jpg',
    );
    expect(
      sm.currentSession?.generatedImages,
      ['/api/img/fotoflashback/only-strip.jpg'],
    );
    expect(
      sm.currentSession?.latestImageUrl,
      '/api/img/fotoflashback/only-strip.jpg',
    );
    expect(
      sm.currentSession?.stripCompositeUrl,
      '/api/img/fotoflashback/only-strip.jpg',
    );

    await sm.attachDeliverableImageUrls(
      imageUrls: const ['data:image/jpeg;base64,xx'],
      stripCompositeUrl: 'https://cdn.example/nope.jpg',
    );
    expect(
      sm.currentSession?.stripCompositeUrl,
      '/api/img/fotoflashback/only-strip.jpg',
    );

    await sm.attachDeliverableImageUrls(
      imageUrls: const ['/api/img/generated/ai.jpg'],
    );
    expect(
      sm.currentSession?.generatedImages,
      [
        '/api/img/fotoflashback/only-strip.jpg',
        '/api/img/generated/ai.jpg',
      ],
    );
    expect(sm.currentSession?.latestImageUrl, '/api/img/generated/ai.jpg');
    expect(
      sm.currentSession?.stripCompositeUrl,
      '/api/img/fotoflashback/only-strip.jpg',
    );
  });

  group('carry-forward is scoped to one session', () {
    Map<String, dynamic> sessionJson(String id) => {
          'id': id,
          'termsAccepted': true,
          'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
          'attemptsUsed': 0,
          'generatedImages': <dynamic>[],
          'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
        };

    test('a new session does not inherit the offline flag', () {
      final sm = SessionManager();
      // Guest 1 ran while the WAN was down.
      sm.setSessionFromResponse({
        ...sessionJson('sess-offline-guest'),
        'offline': true,
      });
      expect(sm.isOfflineSession, isTrue);

      // The same session refreshing keeps the marker; the echo omits it.
      sm.setSessionFromResponse(sessionJson('sess-offline-guest'));
      expect(sm.isOfflineSession, isTrue);

      // Guest 2 was created online and must come back online, or Pick a look
      // serves the fallback catalog and payment claims offline forever.
      sm.setSessionFromResponse(sessionJson('sess-online-guest'));
      expect(sm.sessionId, 'sess-online-guest');
      expect(sm.isOfflineSession, isFalse);
    });

    test('a new session does not inherit the previous guest deliverables', () {
      final sm = SessionManager();
      sm.setSessionFromResponse({
        ...sessionJson('sess-first'),
        'shareToken': 'first-guest-token',
        'personCount': 4,
        'generatedImages': ['/api/img/generated/first-guest.jpg'],
        'latestImageUrl': '/api/img/generated/first-guest.jpg',
        'stripCompositeUrl': '/api/img/fotoflashback/first-guest.jpg',
      });
      expect(sm.shareToken, 'first-guest-token');

      // Handing these to the next guest would show them someone else's photos
      // and a share link into someone else's gallery.
      sm.setSessionFromResponse(sessionJson('sess-second'));
      expect(sm.sessionId, 'sess-second');
      expect(sm.shareToken, isNot('first-guest-token'));
      expect(sm.currentSession?.generatedImages, isEmpty);
      expect(sm.currentSession?.latestImageUrl, isNull);
      expect(sm.currentSession?.stripCompositeUrl, isNull);
      expect(sm.currentSession?.personCount, isNull);
    });

    test('the same session still back-fills a partial echo', () {
      final sm = SessionManager();
      sm.setSessionFromResponse({
        ...sessionJson('sess-same'),
        'shareToken': 'stable-token',
        'generatedImages': ['/api/img/generated/one.jpg'],
        'latestImageUrl': '/api/img/generated/one.jpg',
      });

      // A PATCH echo that omits them must not wipe what we already hold.
      sm.setSessionFromResponse({...sessionJson('sess-same'), 'attemptsUsed': 1});
      expect(sm.shareToken, 'stable-token');
      expect(sm.currentSession?.generatedImages, ['/api/img/generated/one.jpg']);
      expect(sm.currentSession?.latestImageUrl, '/api/img/generated/one.jpg');
      expect(sm.currentSession?.attemptsUsed, 1);
    });
  });
}
