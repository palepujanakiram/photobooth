import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/preprocess_image_result.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_preprocess_helpers.dart';
import 'package:photobooth/services/api_service.dart';
import 'package:photobooth/services/session_manager.dart';
import '../../fakes/fake_api_service.dart';
import 'package:photobooth/utils/print_orientation.dart';
import 'package:photobooth/services/local_session_skeleton.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ignore_for_file: avoid_redundant_argument_values

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SessionManager().clearSession();
    SessionPreprocessCoordinator.instance.reset();
  });
  group('resolvePersonCountAfterPreprocess', () {
    test('prefers preprocess personCount', () {
      expect(
        resolvePersonCountAfterPreprocess(
          preprocess: const PreprocessImageResult(success: true, personCount: 3),
          clientFaceCount: 1,
          sessionPersonCount: 2,
        ),
        3,
      );
    });

    test('uses session personCount when preprocess missing', () {
      expect(
        resolvePersonCountAfterPreprocess(
          preprocess: null,
          clientFaceCount: 0,
          sessionPersonCount: 2,
        ),
        2,
      );
    });

    test('uses client face count when preprocess missing', () {
      expect(
        resolvePersonCountAfterPreprocess(
          preprocess: null,
          clientFaceCount: 2,
        ),
        2,
      );
    });

    test('defaults to solo when no signals', () {
      expect(
        resolvePersonCountAfterPreprocess(
          preprocess: null,
          clientFaceCount: 0,
        ),
        1,
      );
    });
  });

  group('isHardPreprocessFailure', () {
    test('false when preprocess succeeded', () {
      expect(
        isHardPreprocessFailure(
          preprocess: const PreprocessImageResult(success: true),
          clientFaceCount: 0,
        ),
        isFalse,
      );
    });

    test('false when client detected faces', () {
      expect(
        isHardPreprocessFailure(
          preprocess: const PreprocessImageResult(success: false),
          clientFaceCount: 2,
        ),
        isFalse,
      );
    });

    test('true only on explicit failure with no count signals', () {
      expect(
        isHardPreprocessFailure(
          preprocess: const PreprocessImageResult(success: false),
          clientFaceCount: 0,
        ),
        isTrue,
      );
    });

    test('false when session personCount provides signal', () {
      expect(
        isHardPreprocessFailure(
          preprocess: const PreprocessImageResult(success: false),
          clientFaceCount: 0,
          sessionPersonCount: 2,
        ),
        isFalse,
      );
    });

    test('false when preprocess personCount present despite success=false', () {
      expect(
        isHardPreprocessFailure(
          preprocess: const PreprocessImageResult(success: false, personCount: 1),
          clientFaceCount: 0,
        ),
        isFalse,
      );
    });
  });

  group('ensureAuthoritativePersonCount', () {
    test('skips Fly preprocess when the session is offline', () async {
      final sm = SessionManager();
      sm.setSessionFromResponse({
        ..._sessionJson('sess-off'),
        kKioskSessionOfflineKey: true,
      });
      var preprocessCalls = 0;
      await ensureAuthoritativePersonCount(
        sessionManager: sm,
        apiService: ApiService(),
        sessionId: 'sess-off',
        preprocessFn: (_) async {
          preprocessCalls++;
          return const PreprocessImageResult(success: true, personCount: 9);
        },
      );
      expect(preprocessCalls, 0);
      expect(sm.personCount, isNull);
    });

    test('skips preprocess when session already has a group count', () async {
      final sm = SessionManager();
      sm.setSessionFromResponse({
        'id': 'sess-1',
        'termsAccepted': true,
        'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'attemptsUsed': 0,
        'generatedImages': [],
        'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
      });
      sm.setPersonCount(4);

      var preprocessCalls = 0;
      await ensureAuthoritativePersonCount(
        sessionManager: sm,
        apiService: ApiService(),
        sessionId: 'sess-1',
        preprocessFn: (_) async {
          preprocessCalls++;
          return const PreprocessImageResult(success: true, personCount: 1);
        },
      );

      expect(preprocessCalls, 0);
      expect(sm.personCount, 4);
      expect(sm.printOrientation, PrintOrientation.landscape);
    });

    test('updates person count when preprocess succeeds', () async {
      final sm = SessionManager();
      sm.setSessionFromResponse(_sessionJson('sess-pre'));
      await ensureAuthoritativePersonCount(
        sessionManager: sm,
        apiService: ApiService(),
        sessionId: 'sess-pre',
        preprocessFn: (_) async =>
            const PreprocessImageResult(success: true, personCount: 2),
      );
      expect(sm.personCount, 2);
    });

    test('ignores generic preprocess failures', () async {
      final sm = SessionManager();
      sm.setSessionFromResponse(_sessionJson('sess-catch'));
      await ensureAuthoritativePersonCount(
        sessionManager: sm,
        apiService: ApiService(),
        sessionId: 'sess-catch',
        preprocessFn: (_) async => throw StateError('preprocess boom'),
      );
    });

    test('uses api preprocess when override omitted', () async {
      final sm = SessionManager();
      sm.setSessionFromResponse(_sessionJson('sess-api-pre'));
      await ensureAuthoritativePersonCount(
        sessionManager: sm,
        apiService: FakeApiService(),
        sessionId: 'sess-api-pre',
      );
      expect(sm.personCount, 2);
    });

    test('skips a second preprocess after the first completed', () async {
      final sm = SessionManager();
      sm.setSessionFromResponse(_sessionJson('sess-once'));
      var calls = 0;
      Future<PreprocessImageResult> run(_) async {
        calls++;
        return const PreprocessImageResult(success: true, personCount: 1);
      }

      await ensureAuthoritativePersonCount(
        sessionManager: sm,
        apiService: ApiService(),
        sessionId: 'sess-once',
        preprocessFn: run,
      );
      await ensureAuthoritativePersonCount(
        sessionManager: sm,
        apiService: ApiService(),
        sessionId: 'sess-once',
        preprocessFn: run,
      );
      expect(calls, 1);
      expect(sm.personCount, 1);
    });

    test('concurrent ensureAuthoritativePersonCount shares one POST', () async {
      final sm = SessionManager();
      sm.setSessionFromResponse(_sessionJson('sess-join'));
      final gate = Completer<PreprocessImageResult>();
      var calls = 0;
      Future<PreprocessImageResult> run(_) {
        calls++;
        return gate.future;
      }

      final first = ensureAuthoritativePersonCount(
        sessionManager: sm,
        apiService: ApiService(),
        sessionId: 'sess-join',
        preprocessFn: run,
      );
      final second = ensureAuthoritativePersonCount(
        sessionManager: sm,
        apiService: ApiService(),
        sessionId: 'sess-join',
        preprocessFn: run,
      );
      gate.complete(const PreprocessImageResult(success: true, personCount: 2));
      await Future.wait([first, second]);
      expect(calls, 1);
      expect(sm.personCount, 2);
    });

    test('ignores preprocess timeout', () async {
      final sm = SessionManager();
      sm.setSessionFromResponse(_sessionJson('sess-timeout'));
      await ensureAuthoritativePersonCount(
        sessionManager: sm,
        apiService: ApiService(),
        sessionId: 'sess-timeout',
        preprocessFn: (_) async => throw TimeoutException('slow'),
      );
      expect(sm.personCount, isNull);
      expect(
        SessionPreprocessCoordinator.instance.isCompletedFor('sess-timeout'),
        isFalse,
      );
    });

    test('retries preprocess after a timeout so generate can still refine count',
        () async {
      final sm = SessionManager();
      sm.setSessionFromResponse(_sessionJson('sess-retry'));
      var calls = 0;
      await ensureAuthoritativePersonCount(
        sessionManager: sm,
        apiService: ApiService(),
        sessionId: 'sess-retry',
        preprocessFn: (_) async {
          calls++;
          throw TimeoutException('slow');
        },
      );
      await ensureAuthoritativePersonCount(
        sessionManager: sm,
        apiService: ApiService(),
        sessionId: 'sess-retry',
        preprocessFn: (_) async {
          calls++;
          return const PreprocessImageResult(success: true, personCount: 3);
        },
      );
      expect(calls, 2);
      expect(sm.personCount, 3);
    });

    test('runOrJoinSessionPreprocess joins inflight for the same session',
        () async {
      final gate = Completer<PreprocessImageResult>();
      var calls = 0;
      Future<PreprocessImageResult> run(_) {
        calls++;
        return gate.future;
      }

      final first = runOrJoinSessionPreprocess(
        sessionId: 'sess-rj',
        preprocessFn: run,
      );
      final second = runOrJoinSessionPreprocess(
        sessionId: 'sess-rj',
        preprocessFn: run,
      );
      expect(SessionPreprocessCoordinator.instance.inflightFor('other'), isNull);
      gate.complete(const PreprocessImageResult(success: true, personCount: 3));
      expect((await first).personCount, 3);
      expect((await second).personCount, 3);
      expect(calls, 1);
      expect(
        SessionPreprocessCoordinator.instance.isCompletedFor('sess-rj'),
        isTrue,
      );
    });

    test('older preprocess settle does not complete a newer session', () async {
      final firstGate = Completer<PreprocessImageResult>();
      final secondGate = Completer<PreprocessImageResult>();
      final first = SessionPreprocessCoordinator.instance.track(
        sessionId: 'sess-a',
        future: firstGate.future,
      );
      final second = SessionPreprocessCoordinator.instance.track(
        sessionId: 'sess-b',
        future: secondGate.future,
      );
      firstGate.complete(
        const PreprocessImageResult(success: true, personCount: 1),
      );
      await first;
      expect(
        SessionPreprocessCoordinator.instance.isCompletedFor('sess-b'),
        isFalse,
      );
      expect(
        SessionPreprocessCoordinator.instance.inflightFor('sess-b'),
        isNotNull,
      );
      secondGate.complete(
        const PreprocessImageResult(success: true, personCount: 2),
      );
      expect((await second).personCount, 2);
      expect(
        SessionPreprocessCoordinator.instance.isCompletedFor('sess-b'),
        isTrue,
      );
    });
  });

  group('PreprocessImageResult.fromJson', () {
    test('parses success and int personCount', () {
      final r = PreprocessImageResult.fromJson({
        'success': true,
        'personCount': 2,
      });
      expect(r.success, isTrue);
      expect(r.personCount, 2);
      expect(r.framing, isNull);
    });

    test('parses num personCount via round()', () {
      final r = PreprocessImageResult.fromJson({
        'success': true,
        'personCount': 2.7,
      });
      expect(r.personCount, 3);
    });

    test('parses framing map', () {
      final r = PreprocessImageResult.fromJson({
        'success': true,
        'framing': {'x': 10, 'y': 20},
      });
      expect(r.framing, {'x': 10, 'y': 20});
    });

    test('ignores zero personCount', () {
      final r = PreprocessImageResult.fromJson({'success': true, 'personCount': 0});
      expect(r.personCount, isNull);
    });

    test('empty map defaults', () {
      final r = PreprocessImageResult.fromJson({});
      expect(r.success, isFalse);
      expect(r.personCount, isNull);
      expect(r.framing, isNull);
    });
  });
}

Map<String, dynamic> _sessionJson(String sessionId) {
  return {
    'id': sessionId,
    'termsAccepted': true,
    'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
    'attemptsUsed': 0,
    'generatedImages': <dynamic>[],
    'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
  };
}
