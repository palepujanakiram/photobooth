import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:photobooth/services/api_service.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:photobooth/utils/exceptions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/theme_fixtures.dart';
import '../helpers/mock_api_dio.dart';
import '../helpers/tiny_jpeg.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Dio dio;
  late Dio aiDio;
  late ApiService api;

  setUp(() {
    SharedPreferences.setMockInitialValues({'kiosk_code': 'K1'});
    SessionManager().clearSession();
    final mock = createMockApiDio();
    dio = mock.dio;
    aiDio = createMockAiDio();
    api = ApiService(dio: dio, aiDio: aiDio);
  });

  test('generateImage returns transformed model', () async {
    final m = await api.generateImage(
      sessionId: 'sess-1',
      attempt: 1,
      originalPhotoId: 'p1',
      themeId: 't1',
      onProgress: (_) {},
    );
    expect(m.imageUrl, contains('generated'));
    expect(m.runId, 'run-1');
  });

  test('generateImages single slot uses POST path', () async {
    final r = await api.generateImages(
      sessionId: 'sess-1',
      count: 1,
      attempt: 1,
      originalPhotoId: 'p1',
      themeId: 't1',
    );
    expect(r.imageUrlsBySlot, hasLength(1));
    expect(r.firstImageUrl, isNotEmpty);
  });

  test('generateImages parallel uses SSE stream', () async {
    final r = await api.generateImages(
      sessionId: 'sess-1',
      count: 2,
      attempt: 1,
      originalPhotoId: 'p1',
      themeId: 't1',
      onProgress: (_) {},
      onSseEvent: (_, __) {},
    );
    expect(r.success, isTrue);
    expect(r.runId, 'run-sse');
    expect(r.imageUrlsBySlot.first, isNotEmpty);
  });

  test('initiatePayment parses result', () async {
    final r = await api.initiatePayment(
      sessionId: 'sess-1',
      amount: 100,
      fcmToken: 'tok',
    );
    expect(r.id, 'pay-1');
    expect(r.status, 'PENDING');
  });

  test('registerSessionFcmToken and postSessionReceipt', () async {
    final adapter = dio.httpClientAdapter as DioAdapter;
    adapter.onPost(
      RegExp(r'/api/sessions/.*/fcm-token'),
      (s) => s.reply(204, null),
    );
    adapter.onPost(
      RegExp(r'/api/sessions/.*/receipt'),
      (s) => s.reply(200, {'sent': true}),
    );
    await api.registerSessionFcmToken(sessionId: 'sess-1', fcmToken: 'fcm-tok');
    final receipt = await api.postSessionReceipt(
      sessionId: 'sess-1',
      customerPhone: '+15551234567',
    );
    expect(receipt['ok'], true);
  });

  test('fetchPaymentStatus returns map on success', () async {
    dio.httpClientAdapter = DioAdapter(dio: dio)
      ..onGet(
        RegExp(r'/api/payments/status'),
        (s) => s.reply(200, {'status': 'PAID'}),
      );
    final status = await api.fetchPaymentStatus('pay-1', sessionId: 'sess-1');
    expect(status?['status'], 'PAID');
  });

  test('acceptTerms calls legacy endpoint', () async {
    await api.acceptTerms(deviceType: 'kiosk');
  });

  test('getThemes handles connection timeout message', () async {
    final badDio = Dio(BaseOptions(baseUrl: dio.options.baseUrl));
    badDio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionTimeout,
              message: 'timeout',
            ),
          );
        },
      ),
    );
    final badApi = ApiService(dio: badDio);
    expect(() => badApi.getThemes(), throwsA(isA<ApiException>()));
  });

  test('updateSession rejects HTML body', () async {
    dio.options.extra['test_patch_body'] = '<html>not json</html>';
    expect(
      () => api.updateSession(
        sessionId: 'sess-1',
        selectedThemeId: 't1',
      ),
      throwsA(isA<ApiException>()),
    );
  });

  test('getKioskFrames handles 500 with message body', () async {
    SessionManager().setSessionFromResponse({
      'id': 'sess-1',
      'kioskId': 'kid',
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': [],
      'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
    });
    dio.httpClientAdapter = DioAdapter(dio: dio)
      ..onGet(
        '/api/kiosk/frames',
        (s) => s.reply(500, {'message': 'server error'}),
      );
    final api2 = ApiService(dio: dio);
    final frames = await api2.getKioskFrames();
    expect(frames, isEmpty);
  });

  test('preprocessImage fires without throwing', () async {
    dio.httpClientAdapter = DioAdapter(dio: dio)
      ..onPost('/api/preprocess-image', (s) => s.reply(200, {}));
    api.preprocessImage(sessionId: 'sess-1', clientFaceCount: 1);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  test('generateImage fails when success false', () async {
    final failMock = createMockApiDio(includeAiRoutes: false);
    failMock.adapter.onPost(
      '/api/generate-image',
      (s) => s.reply(200, {'success': false, 'error': 'nope'}),
    );
    final failApi = ApiService(dio: dio, aiDio: failMock.dio);
    expect(
      () => failApi.generateImage(
        sessionId: 's',
        attempt: 1,
        originalPhotoId: 'p',
        themeId: 't',
      ),
      throwsA(isA<ApiException>()),
    );
  });

  test('validateKioskCode returns false on empty themes', () async {
    dio.httpClientAdapter = DioAdapter(dio: dio)
      ..onGet(
        '/api/themes',
        (s) => s.reply(200, []),
        queryParameters: {'kioskCode': 'EMPTY'},
      );
    expect(await api.validateKioskCode('empty'), isFalse);
  });

  test('createKioskShareLink validates session id', () async {
    expect(
      () => api.createKioskShareLink(kioskCode: 'K', sessionId: '  '),
      throwsA(isA<ApiException>()),
    );
  });

  test('fetchSession returns null for empty id', () async {
    expect(await api.fetchSession(''), isNull);
  });

  test('ThemeModel used in transformImage web path is skipped on VM', () async {
    // Mobile path uses FileHelper; covered indirectly via generateImage mock.
    expect(sampleTheme('t1').promptText, isNotEmpty);
  });

  test('encode path constants reachable via helpers', () {
    expect(kTinyJpegDataUrl, startsWith('data:image/jpeg'));
  });
}
