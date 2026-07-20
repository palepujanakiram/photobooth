import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/preprocess_image_result.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_preprocess_helpers.dart';
import 'package:photobooth/services/api_service.dart';
import 'package:photobooth/services/session_manager.dart';
import '../../fakes/fake_api_service.dart';
import 'package:photobooth/utils/print_orientation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ignore_for_file: avoid_redundant_argument_values

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SessionManager().clearSession();
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
