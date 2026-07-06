import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:photobooth/services/api_service.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:photobooth/utils/exceptions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/mock_api_dio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Dio dio;
  late DioAdapter adapter;
  late ApiService api;

  setUp(() {
    SharedPreferences.setMockInitialValues({'kiosk_code': 'KIOSK1'});
    SessionManager().clearSession();
    final mock = createMockApiDio();
    dio = mock.dio;
    adapter = mock.adapter;
    api = ApiService(dio: dio);
  });

  test('validateKioskCode returns false for empty', () async {
    expect(await api.validateKioskCode('  '), isFalse);
  });

  test('validateKioskCode true when themes list non-empty', () async {
    adapter.onGet(
      '/api/themes',
      (s) => s.reply(200, [
        {'id': 't1', 'categoryId': 'c', 'name': 'T', 'description': 'd', 'promptText': 'p'},
      ]),
      queryParameters: {'kioskCode': 'ABC'},
    );
    expect(await api.validateKioskCode('abc'), isTrue);
  });

  test('getThemes parses list', () async {
    adapter.onGet(
      '/api/themes',
      (s) => s.reply(200, [
        {
          'id': 't1',
          'categoryId': 'c1',
          'name': 'Theme',
          'description': 'd',
          'promptText': 'prompt',
        },
      ]),
    );
    final themes = await api.getThemes();
    expect(themes, hasLength(1));
    expect(themes.first.id, 't1');
  });

  test('getThemes throws on unexpected body', () async {
    adapter.onGet('/api/themes', (s) => s.reply(200, {'oops': true}));
    expect(() => api.getThemes(), throwsA(isA<ApiException>()));
  });

  test('fetchKioskByCode returns model when valid', () async {
    adapter.onGet(
      '/api/kiosk/by-code/XYZ',
      (s) => s.reply(200, {'id': 'k1', 'code': 'XYZ', 'name': 'Lobby'}),
    );
    final info = await api.fetchKioskByCode('xyz');
    expect(info?.code, 'XYZ');
  });

  test('fetchKioskByCode null on 404', () async {
    adapter.onGet('/api/kiosk/by-code/BAD', (s) => s.reply(404, {}));
    expect(await api.fetchKioskByCode('bad'), isNull);
  });

  test('getKioskFrames parses list and wrapper', () async {
    SessionManager().setSessionFromResponse({
      'id': 'sess-1',
      'kioskId': 'kid-1',
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': [],
      'expiresAt': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
    });
    adapter.onGet(
      '/api/kiosk/frames',
      (s) => s.reply(200, {
        'frames': [
          {'id': 'f1', 'name': 'F', 'overlayUrl': 'https://cdn/o.png'},
        ],
      }),
    );
    final frames = await api.getKioskFrames();
    expect(frames, hasLength(1));
    expect(frames.first.id, 'f1');
  });

  test('getKioskFrames throws when kiosk context missing', () async {
    SharedPreferences.setMockInitialValues({});
    SessionManager().clearSession();
    expect(() => api.getKioskFrames(), throwsA(isA<ApiException>()));
  });

  test('updateSession parses JSON response', () async {
    dio.options.extra['test_patch_body'] =
        '{"sessionId":"sess-1","selectedThemeId":"t1"}';
    final body = await api.updateSession(
      sessionId: 'sess-1',
      selectedThemeId: 't1',
    );
    expect(body['sessionId'], 'sess-1');
    expect(body['selectedThemeId'], 't1');
  });

  test('updateSession requires at least one field', () async {
    expect(
      () => api.updateSession(sessionId: 's1'),
      throwsA(isA<ApiException>()),
    );
  });

  test('fetchGenerationRun returns map', () async {
    adapter.onGet(
      '/api/generation-runs/run-9',
      (s) => s.reply(200, {'id': 'run-9', 'status': 'done'}),
    );
    final run = await api.fetchGenerationRun('run-9');
    expect(run['id'], 'run-9');
  });

  test('fetchGenerationRun rejects empty id', () async {
    expect(() => api.fetchGenerationRun(' '), throwsA(isA<ApiException>()));
  });

  test('fetchKioskGenerationTiming parses map', () async {
    SessionManager().setSessionFromResponse({
      'id': 'sess-1',
      'kioskId': 'kid-1',
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': [],
      'expiresAt': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
    });
    adapter.onGet(
      '/api/kiosk/generation-timing',
      (s) => s.reply(200, {
        'p50Seconds': 78,
        'p90Seconds': 142,
        'lastHourAvgSeconds': 95,
        'todayAvgSeconds': 88,
        'sampleCountLastHour': 12,
        'sampleCountToday': 40,
        'sampleCountWeek': 120,
        'busy': false,
      }),
    );
    final timing = await api.fetchKioskGenerationTiming();
    expect(timing['p50Seconds'], 78);
    expect(timing['busy'], isFalse);
  });

  test('fetchKioskGenerationTiming throws when kiosk context missing', () async {
    SharedPreferences.setMockInitialValues({});
    SessionManager().clearSession();
    expect(
      () => api.fetchKioskGenerationTiming(),
      throwsA(isA<ApiException>()),
    );
  });

  test('fetchSession parses map', () async {
    adapter.onGet(
      '/api/sessions/sess-2',
      (s) => s.reply(200, {'id': 'sess-2', 'status': 'open'}),
    );
    final session = await api.fetchSession('sess-2');
    expect(session?['id'], 'sess-2');
  });

  test('deleteSession succeeds', () async {
    adapter.onDelete('/api/sessions/sess-3', (s) => s.reply(204, null));
    await api.deleteSession('sess-3');
  });

  test('createKioskShareLink validates inputs', () async {
    expect(
      () => api.createKioskShareLink(kioskCode: '', sessionId: 's'),
      throwsA(isA<ApiException>()),
    );
  });

  test('getAppSettings via retrofit client', () async {
    adapter.onGet(
      '/api/settings',
      (s) => s.reply(200, {'parallelImageCount': 2, 'printerEnabled': false}),
    );
    final settings = await api.getAppSettings();
    expect(settings.parallelImageCount, 2);
  });

  test('acceptTermsAndCreateSession returns map', () async {
    final body = await api.acceptTermsAndCreateSession(kioskCode: 'K1');
    expect(body['id'], 'sess-new');
  });

  test('createKioskShareLink posts and returns map', () async {
    adapter.onPost(
      '/api/kiosk/shares',
      (s) => s.reply(200, {'token': 'tok', 'url': 'https://s/tok'}),
      data: {'kioskCode': 'K1', 'sessionId': 'sess-1'},
    );
    final link = await api.createKioskShareLink(
      kioskCode: 'k1',
      sessionId: 'sess-1',
    );
    expect(link['token'], 'tok');
  });
}
