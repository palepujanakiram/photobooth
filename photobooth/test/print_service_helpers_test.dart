import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/print_service_helpers.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('lanPrintResponseUncertainButJobLikelySent', () {
    test('receiveTimeout means job likely accepted', () {
      expect(
        lanPrintResponseUncertainButJobLikelySent(
          DioException(
            requestOptions: RequestOptions(path: '/api/PrintImage'),
            type: DioExceptionType.receiveTimeout,
          ),
        ),
        isTrue,
      );
    });

    test('connection reset after accept means job likely accepted', () {
      expect(
        lanPrintResponseUncertainButJobLikelySent(
          DioException(
            requestOptions: RequestOptions(path: '/api/PrintImage'),
            type: DioExceptionType.connectionError,
            message: 'Connection reset by peer',
          ),
        ),
        isTrue,
      );
    });

    test('connection refused is a real failure', () {
      expect(
        lanPrintResponseUncertainButJobLikelySent(
          DioException(
            requestOptions: RequestOptions(path: '/api/PrintImage'),
            type: DioExceptionType.connectionError,
            message: 'Connection refused',
          ),
        ),
        isFalse,
      );
    });

    test('connection timeout before send is a real failure', () {
      expect(
        lanPrintResponseUncertainButJobLikelySent(
          DioException(
            requestOptions: RequestOptions(path: '/api/PrintImage'),
            type: DioExceptionType.connectionTimeout,
          ),
        ),
        isFalse,
      );
    });
  });

  group('resolveRemoteImageUrlForPrint', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      SessionManager().clearSession();
    });

    tearDown(() {
      SessionManager().clearSession();
    });

    test('adds sessionId to protected generated image URLs', () {
      SessionManager().setSessionFromResponse({
        'id': 'sess-print-1',
        'termsAccepted': true,
        'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'attemptsUsed': 0,
        'generatedImages': [],
        'expiresAt': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
      });
      final url = resolveRemoteImageUrlForPrint(
        '/api/img/generated/abc.jpg',
      );
      expect(url, contains('sessionId=sess-print-1'));
      expect(url, contains('/api/img/generated/abc.jpg'));
      expect(url, startsWith('https://'));
    });

    test('preserves existing sessionId query param', () {
      SessionManager().setSessionFromResponse({
        'id': 'other',
        'termsAccepted': true,
        'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'attemptsUsed': 0,
        'generatedImages': [],
        'expiresAt': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
      });
      final url = resolveRemoteImageUrlForPrint(
        'https://fotozenai.fly.dev/api/img/generated/abc.jpg?sessionId=existing',
      );
      expect(url, contains('sessionId=existing'));
      expect(url, isNot(contains('sessionId=other')));
    });
  });
}
