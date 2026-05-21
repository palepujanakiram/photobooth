import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/theme_selection/theme_model.dart';
import 'package:photobooth/services/api_service_helpers.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:photobooth/utils/exceptions.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'kiosk_code': 'K1'});
    SessionManager().clearSession();
  });

  test('kioskThemesQueryParameters includes kiosk code and session kioskId', () async {
    SessionManager().setSessionFromResponse({
      'id': 'sess-1',
      'kioskId': 'kid-1',
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': [],
      'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
    });
    final qp = await kioskThemesQueryParameters();
    expect(qp['kioskCode'], 'K1');
    expect(qp['kioskId'], 'kid-1');
  });

  test('parseThemesResponseBody maps list of maps', () {
    final themes = parseThemesResponseBody([
      {
        'id': 't1',
        'categoryId': 'c1',
        'name': 'Theme',
        'description': 'd',
        'promptText': 'p',
      },
    ]);
    expect(themes, hasLength(1));
    expect(themes.first.id, isNotEmpty);
  });

  test('parseThemesResponseBody throws on unexpected shape', () {
    expect(
      () => parseThemesResponseBody({'not': 'list'}),
      throwsA(isA<ApiException>()),
    );
  });

  test('rethrowThemesFetchDioError maps connection and generic errors', () {
    expect(
      () => rethrowThemesFetchDioError(
        DioException(
          requestOptions: RequestOptions(path: '/api/themes'),
          type: DioExceptionType.connectionTimeout,
          message: 'timeout',
        ),
      ),
      throwsA(
        predicate<ApiException>((e) => e.message.contains('Connection error')),
      ),
    );
    expect(
      () => rethrowThemesFetchDioError(
        DioException(
          requestOptions: RequestOptions(path: '/api/themes'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/themes'),
            statusCode: 500,
          ),
          message: 'server',
        ),
      ),
      throwsA(
        predicate<ApiException>((e) => e.message.contains('Failed to fetch themes')),
      ),
    );
  });

  test('isWebCorsThemesFetchError and isThemesFetchConnectionError', () {
    final connection = DioException(
      requestOptions: RequestOptions(path: '/'),
      type: DioExceptionType.connectionError,
    );
    expect(isThemesFetchConnectionError(connection), isTrue);
    expect(
      isWebCorsThemesFetchError(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionError,
          message: 'CORS policy',
        ),
        platformIsWeb: true,
      ),
      isTrue,
    );
    expect(
      () => rethrowThemesFetchDioError(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.unknown,
          message: 'NetworkError blocked',
        ),
        platformIsWeb: true,
      ),
      throwsA(predicate<ApiException>((e) => e.message.contains('CORS Error'))),
    );
    expect(
      isWebCorsThemesFetchError(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.badResponse,
        ),
        platformIsWeb: true,
      ),
      isFalse,
    );
  });

  test('decodeSessionPatchResponseText can decode on main isolate', () async {
    final map = await decodeSessionPatchResponseText(
      '{"sessionId":"s"}',
      decodeOnMainIsolate: true,
    );
    expect(map['sessionId'], 's');
  });

  test('buildSessionPatchBody validates and builds fields', () {
    expect(
      () => buildSessionPatchBody(),
      throwsA(isA<ApiException>()),
    );
    final body = buildSessionPatchBody(
      userImageUrl: 'u',
      selectedThemeId: 't',
      includeSelectedFrameId: true,
      selectedFrameId: 'f',
      personCount: 2,
      framingMetadata: {'k': 'v'},
    );
    expect(body['userImageUrl'], 'u');
    expect(body['selectedThemeId'], 't');
    expect(body['selectedFrameId'], 'f');
    expect(body['personCount'], 2);
    expect(body['framingMetadata'], {'k': 'v'});
  });

  test('decodeSessionPatchResponseText parses JSON', () async {
    final map = await decodeSessionPatchResponseText(
      '{"sessionId":"s","selectedThemeId":"t"}',
    );
    expect(map['sessionId'], 's');
    expect(
      () => decodeSessionPatchResponseText(''),
      throwsA(isA<ApiException>()),
    );
  });

  test('logGenerateImageResponseMetadata logs and early-returns', () {
    logGenerateImageResponseMetadata({});
    logGenerateImageResponseMetadata({
      'runId': 'r1',
      'framing': {
        'personCount': 1,
        'orientation': 'portrait',
        'zoomLevel': 'medium',
        'aspectRatio': '4:5',
      },
      'timing': {'totalMs': 100, 'generationMs': 80, 'upscaleMs': 5},
      'faceVerification': {
        'originalCount': 1,
        'generatedCount': 1,
        'match': true,
      },
      'evaluation': {
        'compositeScore': 0.9,
        'identityScore': 0.8,
        'promptScore': 0.7,
      },
    });
  });
}
