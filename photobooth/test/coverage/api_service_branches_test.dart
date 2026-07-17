import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:photobooth/services/api_service.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/utils/exceptions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/mock_api_dio.dart';
import '../helpers/tiny_jpeg.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Dio dio;
  late DioAdapter adapter;
  late ApiService api;

  setUp(() {
    SharedPreferences.setMockInitialValues({'kiosk_code': 'K1'});
    SessionManager().clearSession();
    final mock = createMockApiDio();
    dio = mock.dio;
    adapter = mock.adapter;
    api = ApiService(dio: dio);
  });

  test('registerSessionFcmToken no-op for empty ids', () async {
    await api.registerSessionFcmToken(sessionId: '', fcmToken: 't');
    await api.registerSessionFcmToken(sessionId: 's', fcmToken: ' ');
  });

  test('registerSessionFcmToken logs dio errors without throwing', () async {
    final bad = Dio(BaseOptions(baseUrl: dio.options.baseUrl));
    bad.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) => h.reject(
          DioException(requestOptions: o, message: 'fail'),
        ),
      ),
    );
    await ApiService(dio: bad).registerSessionFcmToken(
      sessionId: 'sess-1',
      fcmToken: 'tok',
    );
  });

  test('postSessionReceipt validates sessionId and optional fields', () async {
    expect(
      () => api.postSessionReceipt(sessionId: ''),
      throwsA(isA<ApiException>()),
    );
    final receipt = await api.postSessionReceipt(
      sessionId: 'sess-1',
      customerName: '  ',
      customerPhone: '+1',
      whatsappOptIn: true,
      transactionRef: 'ref',
      fcmToken: 'fcm',
    );
    expect(receipt['ok'], true);
  });

  test('postSessionPrintReceipt validates sessionId', () async {
    expect(
      () => api.postSessionPrintReceipt(sessionId: ''),
      throwsA(isA<ApiException>()),
    );
  });

  test('fetchPaymentStatus returns null for empty id', () async {
    expect(await api.fetchPaymentStatus(''), isNull);
  });

  test('fetchPaymentStatus returns null on dio error', () async {
    adapter.onGet(
      RegExp(r'/api/payments/status/.*'),
      (s) => s.reply(500, {'message': 'err'}),
    );
    expect(await api.fetchPaymentStatus('pay-1', sessionId: 'sess-1'), isNull);
  });

  test('createKioskShareLink with ttl and imageIndex', () async {
    adapter.onPost(
      '/api/kiosk/shares',
      (s) => s.reply(200, {'token': 't', 'url': 'https://s/t'}),
      data: {
        'kioskCode': 'K1',
        'sessionId': 'sess-1',
        'ttlMinutes': 30,
        'imageIndex': 1,
      },
    );
    final link = await api.createKioskShareLink(
      kioskCode: 'k1',
      sessionId: 'sess-1',
      ttlMinutes: 30,
      imageIndex: 1,
    );
    expect(link['token'], 'tok');
  });

  test('updateSession with framing metadata and frame id', () async {
    dio.options.extra['test_patch_body'] = jsonEncode({
      'sessionId': 'sess-1',
      'selectedFrameId': 'f1',
      'userImageUrl': kTinyJpegDataUrl,
    });
    final body = await api.updateSession(
      sessionId: 'sess-1',
      userImageUrl: kTinyJpegDataUrl,
      includeSelectedFrameId: true,
      selectedFrameId: 'f1',
      personCount: 2,
      framingMetadata: {'orientation': 'portrait'},
    );
    expect(body['sessionId'], 'sess-1');
  });

  test('updateSession rejects empty body', () async {
    expect(
      () => api.updateSession(sessionId: 'sess-1'),
      throwsA(isA<ApiException>()),
    );
  });

  test('updateSession rejects empty response', () async {
    final plain = Dio(
      BaseOptions(
        baseUrl: AppConstants.kBaseUrl,
        validateStatus: (_) => true,
      ),
    );
    plain.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.method == 'PATCH') {
            handler.resolve(
              Response(requestOptions: options, statusCode: 200, data: ''),
            );
            return;
          }
          handler.next(options);
        },
      ),
    );
    final plainApi = ApiService(dio: plain);
    expect(
      () => plainApi.updateSession(sessionId: 'sess-1', selectedThemeId: 't1'),
      throwsA(isA<ApiException>()),
    );
  });

  test('getThemes with kiosk query params', () async {
    SessionManager().setSessionFromResponse({
      'id': 'sess-1',
      'kioskId': 'kid-1',
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': [],
      'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
    });
    adapter.onGet(
      '/api/themes',
      (s) => s.reply(200, [
        {
          'id': 't1',
          'categoryId': 'c',
          'name': 'T',
          'description': 'd',
          'promptText': 'p',
        },
      ]),
    );
    final themes = await api.getThemes();
    expect(themes, hasLength(1));
  });

  test('getKioskFrames throws on 404 with message', () async {
    SessionManager().setSessionFromResponse({
      'id': 'sess-1',
      'kioskId': 'kid',
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': [],
      'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
    });
    adapter.onGet(
      '/api/kiosk/frames',
      (s) => s.reply(404, {'message': 'not found'}),
    );
    expect(() => api.getKioskFrames(), throwsA(isA<ApiException>()));
  });

  test('fetchSession returns map when retrofit gets JSON body', () async {
    adapter.onGet('/api/sessions/sess-x', (s) => s.reply(200, {'id': 'sess-x'}));
    expect((await api.fetchSession('sess-x'))?['id'], 'sess-x');
  });

  test('preprocessImage fires POST', () async {
    adapter.onPost('/api/preprocess-image', (s) => s.reply(200, {}));
    api.preprocessImage(sessionId: 'sess-1', clientFaceCount: 2);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  test('generateImageParallelStream handles error event', () async {
    final failMock = createMockApiDio(includeAiRoutes: false);
    const sse = 'event: error\n'
        'data: {"message":"failed"}\n\n';
    failMock.adapter.onGet(
      '/api/generate-stream-parallel',
      (s) => s.reply(
        200,
        ResponseBody.fromString(sse, 200, headers: {
          Headers.contentTypeHeader: ['text/event-stream'],
        }),
      ),
      queryParameters: {'sessionId': 'sess-1', 'count': 2},
    );
    final failApi = ApiService(dio: dio, aiDio: failMock.dio);
    expect(
      () => failApi.generateImageParallelStream(
        sessionId: 'sess-1',
        count: 2,
        originalPhotoId: 'p',
        themeId: 't',
      ),
      throwsA(isA<ApiException>()),
    );
  });

  test('createKioskShareLink maps dio errors', () async {
    final bad = Dio(BaseOptions(baseUrl: dio.options.baseUrl));
    bad.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) => h.reject(
          DioException(requestOptions: o, message: 'network'),
        ),
      ),
    );
    expect(
      () => ApiService(dio: bad).createKioskShareLink(
        kioskCode: 'K',
        sessionId: 's',
      ),
      throwsA(isA<ApiException>()),
    );
  });

  test('getThemes throws on unexpected response shape', () async {
    adapter.onGet('/api/themes', (s) => s.reply(200, {'not': 'list'}));
    expect(() => api.getThemes(), throwsA(isA<ApiException>()));
  });

  test('validateKioskCode returns false on network error', () async {
    final bad = Dio(BaseOptions(baseUrl: dio.options.baseUrl));
    bad.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) => h.reject(
          DioException(
            requestOptions: o,
            type: DioExceptionType.connectionError,
          ),
        ),
      ),
    );
    expect(await ApiService(dio: bad).validateKioskCode('K'), isFalse);
  });

  test('fetchKioskByCode returns null for invalid payload', () async {
    adapter.onGet('/api/kiosk/by-code/BAD', (s) => s.reply(200, {'id': '', 'code': ''}));
    expect(await api.fetchKioskByCode('bad'), isNull);
  });

  test('getKioskFrames 500 with invalid frame returns empty', () async {
    SessionManager().setSessionFromResponse({
      'id': 'sess-1',
      'kioskId': 'kid',
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': [],
      'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
    });
    adapter.onGet(
      '/api/kiosk/frames',
      (s) => s.reply(500, {
        'frames': [{'id': '', 'name': 'x', 'overlayUrl': ''}],
      }),
    );
    expect(await api.getKioskFrames(), isEmpty);
  });

  test('getKioskFrames throws when body is not a list', () async {
    SessionManager().setSessionFromResponse({
      'id': 'sess-1',
      'kioskId': 'kid',
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': [],
      'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
    });
    adapter.onGet('/api/kiosk/frames', (s) => s.reply(200, {'oops': true}));
    expect(() => api.getKioskFrames(), throwsA(isA<ApiException>()));
  });

  test('generateImage retries once on timeout', () async {
    var calls = 0;
    final failMock = createMockApiDio(includeAiRoutes: false);
    failMock.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path.contains('generate-image')) {
            calls++;
            if (calls == 1) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.receiveTimeout,
                ),
              );
              return;
            }
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'success': true,
                  'imageUrl': '/api/img/x.jpg',
                  'runId': 'r1',
                },
              ),
            );
            return;
          }
          handler.next(options);
        },
      ),
    );
    final retryApi = ApiService(dio: dio, aiDio: failMock.dio);
    final m = await retryApi.generateImage(
      sessionId: 'sess-1',
      attempt: 1,
      originalPhotoId: 'p',
      themeId: 't',
    );
    expect(m.imageUrl, contains('/api/img/x.jpg'));
    expect(calls, 2);
  });

  test('postSessionReceipt sends marketing and optional contact fields', () async {
    Map<String, dynamic>? seen;
    final custom = Dio(
      BaseOptions(
        baseUrl: AppConstants.kBaseUrl,
        validateStatus: (_) => true,
      ),
    );
    final customAdapter = DioAdapter(dio: custom);
    custom.httpClientAdapter = customAdapter;
    custom.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.data is Map) {
            seen = Map<String, dynamic>.from(options.data as Map);
          }
          handler.next(options);
        },
      ),
    );
    customAdapter.onPost(
      RegExp(r'/api/sessions/.*/receipt'),
      (s) => s.reply(200, {'ok': true}),
      data: Matchers.any,
    );
    final receiptApi = ApiService(dio: custom, aiDio: custom);
    await receiptApi.postSessionReceipt(
      sessionId: 'sess-1',
      customerName: 'Ada',
      customerPhone: '+9198',
      customerEmail: 'a@b.co',
      customerUpiVpa: 'ada@upi',
      whatsappOptIn: true,
      marketingEmailOptIn: true,
      marketingSmsOptIn: false,
      marketingWhatsappOptIn: true,
      fcmToken: 'fcm',
    );
    expect(seen?['customerEmail'], 'a@b.co');
    expect(seen?['customerUpiVpa'], 'ada@upi');
    expect(seen?['marketingEmailOptIn'], true);
    expect(seen?['marketingSmsOptIn'], false);
    expect(seen?['marketingWhatsappOptIn'], true);
  });

  test('applySessionDiscount validates and posts body', () async {
    expect(
      () => api.applySessionDiscount(sessionId: '', code: 'X', subtotal: 10),
      throwsA(isA<ApiException>()),
    );
    expect(
      () => api.applySessionDiscount(sessionId: 's', code: '', subtotal: 10),
      throwsA(isA<ApiException>()),
    );
    expect(
      () => api.applySessionDiscount(sessionId: 's', code: 'X', subtotal: 0),
      throwsA(isA<ApiException>()),
    );
    final r = await api.applySessionDiscount(
      sessionId: 'sess-1',
      code: 'FEST20',
      subtotal: 100,
    );
    expect(r['finalAmount'], 80);
  });

  test('unapplySessionDiscount and fetchSessionDiscount', () async {
    expect(
      () => api.unapplySessionDiscount(sessionId: ''),
      throwsA(isA<ApiException>()),
    );
    expect(
      () => api.fetchSessionDiscount(sessionId: ''),
      throwsA(isA<ApiException>()),
    );
    final u = await api.unapplySessionDiscount(sessionId: 'sess-1');
    expect(u['success'], true);
    final g = await api.fetchSessionDiscount(sessionId: 'sess-1');
    expect(g['applied'], false);
  });

}
