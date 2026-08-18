import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:photobooth/services/event_manager.dart';
import 'package:photobooth/services/event_station_api.dart';
import 'package:photobooth/services/kiosk_manager.dart';
import 'package:photobooth/utils/exceptions.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Dio dio;
  late DioAdapter adapter;
  late EventStationApi api;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    EventManager.resetCacheForTests();
    await KioskManager().setKioskCode('K1');
    await EventManager().setEventCode('GALA');
    dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test',
        validateStatus: (_) => true,
      ),
    );
    adapter = DioAdapter(dio: dio);
    api = EventStationApi(
      dio: dio,
      readKioskCode: () async => 'K1',
      readEventCode: () async => 'GALA',
      eventManager: EventManager(),
      kioskManager: KioskManager(),
    );
  });

  test('listThemeJobs parses payload', () async {
    adapter.onGet(
      '/api/event/station/theme-jobs',
      (s) => s.reply(200, {
        'jobs': [
          {'id': 'j1', 'sessionId': 's1', 'status': 'PENDING'},
        ],
      }),
      queryParameters: {
        'kioskCode': 'K1',
        'eventCode': 'GALA',
        'status': 'PENDING',
      },
    );
    final jobs = await api.listThemeJobs();
    expect(jobs.single.id, 'j1');
  });

  test('claim and complete theme job', () async {
    adapter.onPost(
      '/api/event/station/theme-jobs/j1/claim',
      (s) => s.reply(200, {
        'job': {'id': 'j1', 'sessionId': 's1', 'status': 'CLAIMED'},
        'previewUrls': ['https://cdn/a.jpg'],
      }),
      data: Matchers.any,
    );
    adapter.onPost(
      '/api/event/station/theme-jobs/j1/complete',
      (s) => s.reply(200, {
        'job': {'id': 'j1', 'status': 'DONE'},
      }),
      data: Matchers.any,
    );
    final claimed = await api.claimThemeJob('j1');
    expect(claimed.status, 'CLAIMED');
    await api.completeThemeJob(jobId: 'j1', themeId: 't1');
  });

  test('print job list claim complete and errors', () async {
    adapter.onGet(
      '/api/event/station/print-jobs',
      (s) => s.reply(200, {
        'jobs': [
          {
            'id': 'p1',
            'sessionId': 's1',
            'imageUrl': 'https://cdn/p.jpg',
          },
        ],
      }),
      queryParameters: {
        'kioskCode': 'K1',
        'eventCode': 'GALA',
      },
    );
    adapter.onPost(
      '/api/event/station/print-jobs/p1/claim',
      (s) => s.reply(200, {
        'job': {
          'id': 'p1',
          'sessionId': 's1',
          'imageUrl': 'https://cdn/p.jpg',
        },
      }),
      data: Matchers.any,
    );
    adapter.onPost(
      '/api/event/station/print-jobs/p1/complete',
      (s) => s.reply(200, {'ok': true}),
      data: Matchers.any,
    );
    expect((await api.listPrintJobs()).single.id, 'p1');
    expect((await api.claimPrintJob('p1')).imageUrl, 'https://cdn/p.jpg');
    await api.completePrintJob(jobId: 'p1', success: false, error: 'jam');
  });

  test('throws mapped API error and missing codes', () async {
    adapter.onGet(
      '/api/event/station/theme-jobs',
      (s) => s.reply(409, {'error': 'busy'}),
      queryParameters: {
        'kioskCode': 'K1',
        'eventCode': 'GALA',
        'status': 'PENDING',
      },
    );
    expect(
      () => api.listThemeJobs(),
      throwsA(isA<ApiException>().having((e) => e.message, 'msg', 'busy')),
    );

    SharedPreferences.setMockInitialValues({});
    EventManager.resetCacheForTests();
    final empty = EventStationApi(
      dio: dio,
      readKioskCode: () async => '',
      readEventCode: () async => '',
    );
    expect(() => empty.listPrintJobs(), throwsA(isA<ApiException>()));
  });

  test('claim rejects invalid bodies with fallback', () async {
    adapter.onPost(
      '/api/event/station/theme-jobs/j1/claim',
      (s) => s.reply(200, {'nope': true}),
      data: Matchers.any,
    );
    adapter.onPost(
      '/api/event/station/print-jobs/p1/claim',
      (s) => s.reply(500, 'down'),
      data: Matchers.any,
    );
    expect(() => api.claimThemeJob('j1'), throwsA(isA<ApiException>()));
    expect(() => api.claimPrintJob('p1'), throwsA(isA<ApiException>()));
  });
}
