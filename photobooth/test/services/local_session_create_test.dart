import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/local_kiosk_store.dart';
import 'package:photobooth/services/local_session_create.dart';
import 'package:photobooth/services/local_session_skeleton.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/utils/exceptions.dart';

void main() {
  test('skeleton and slim payload', () {
    final now = DateTime.utc(2026, 8, 23, 6);
    final json = localSessionSkeleton(id: 'abc', now: now);
    expect(json['id'], 'abc');
    expect(json['termsAccepted'], isTrue);
    expect(json[kKioskSessionOfflineKey], isTrue);
    expect(json['attemptsUsed'], 0);
    expect(json['generatedImages'], isEmpty);
    expect(json['termsAcceptedAt'], now.toIso8601String());
    expect(
      json['expiresAt'],
      now.add(kLocalSessionTtl).toIso8601String(),
    );
    final slim = slimSessionPayload({
      'id': 'abc',
      'userImageUrl': 'data:',
      'compressedImageUrl': 'data:',
      'selectedThemeId': 't1',
    });
    expect(slim.containsKey('userImageUrl'), isFalse);
    expect(slim.containsKey('compressedImageUrl'), isFalse);
    expect(slim['selectedThemeId'], 't1');
  });

  test('skeleton uses DateTime.now when now omitted', () {
    final json = localSessionSkeleton(id: 'n');
    expect(json['id'], 'n');
    expect(DateTime.parse(json['expiresAt'] as String).isAfter(DateTime.now()),
        isTrue);
  });

  test('wan-down detection', () {
    expect(isWanDownSessionError(TimeoutException('t')), isTrue);
    expect(isWanDownSessionError(ApiException('x')), isTrue);
    expect(isWanDownSessionError(ApiException('x', 500)), isTrue);
    expect(isWanDownSessionError(ApiException('x', 503)), isTrue);
    expect(
      isWanDownSessionError(ApiException(AppConstants.kErrorNetwork, 400)),
      isTrue,
    );
    expect(isWanDownSessionError(ApiException('nope', 400)), isFalse);
    expect(isWanDownSessionError(ApiException('nope', 409)), isFalse);
    expect(isWanDownSessionError(StateError('boom')), isFalse);
  });

  test('createKioskSession uses remote id when Fly answers', () async {
    final dir = await Directory.systemTemp.createTemp('fz_sess_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final store = LocalKioskStore(
      resolveDirectory: () async => dir,
      newId: () => 'ob-1',
      nowMs: () => 1,
    );
    final result = await createKioskSession(
      store: store,
      newId: () => 'client-1',
      kioskCode: 'K1',
      now: DateTime.utc(2026, 8, 23),
      acceptTerms: (id) async {
        expect(id, 'client-1');
        return {
          'id': 'client-1',
          'kioskAuthToken': 'tok',
          'termsAccepted': true,
        };
      },
    );
    expect(result.usedLocalFallback, isFalse);
    expect(result.sessionJson['kioskAuthToken'], 'tok');
    expect((await store.currentSessionJson())!['kioskAuthToken'], 'tok');
  });

  test('createKioskSession falls back when WAN is down', () async {
    final result = await createKioskSession(
      newId: () => 'offline-1',
      now: DateTime.utc(2026, 8, 23),
      acceptTerms: (_) async => throw ApiException('Network error occurred'),
    );
    expect(result.usedLocalFallback, isTrue);
    expect(result.sessionJson['id'], 'offline-1');
  });

  test('createKioskSession keeps client id if Fly omits id', () async {
    final result = await createKioskSession(
      newId: () => 'client-2',
      acceptTerms: (_) async => {'termsAccepted': true, 'id': '  '},
    );
    expect(result.usedLocalFallback, isFalse);
    expect(result.sessionJson['id'], '  ');
  });

  test('createKioskSession rethrows 4xx and clears current', () async {
    final dir = await Directory.systemTemp.createTemp('fz_sess_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final store = LocalKioskStore(
      resolveDirectory: () async => dir,
      newId: () => 'ob-2',
      nowMs: () => 2,
    );
    await expectLater(
      createKioskSession(
        store: store,
        newId: () => 'client-3',
        acceptTerms: (_) async => throw ApiException('bad kiosk', 400),
      ),
      throwsA(isA<ApiException>()),
    );
    expect(await store.currentSessionJson(), isNull);
    expect(await store.getSession('client-3'), isNotNull);
  });

  test('createKioskSession default uuid and 5xx fallback', () async {
    final result = await createKioskSession(
      acceptTerms: (_) async => throw ApiException('down', 502),
    );
    expect(result.usedLocalFallback, isTrue);
    expect((result.sessionJson['id'] as String).length, greaterThan(8));
  });
}
