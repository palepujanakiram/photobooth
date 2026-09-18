import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_pipeline/media_item.dart';
import 'package:photobooth/screens/event_pipeline/event_queue_viewmodel.dart';
import 'package:photobooth/services/event_manager.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_align_api.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_aligner.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_config.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_db.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_ledger.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_queue.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_runner.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_stats.dart';
import 'package:photobooth/services/kiosk_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class JsonAdapter implements HttpClientAdapter {
  JsonAdapter({this.statusCode = 200, this.body, this.throwOnSend = false});

  int statusCode;
  Object? body;
  bool throwOnSend;
  String? lastPath;
  String lastBody = '';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastPath = options.path;
    if (throwOnSend) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    if (requestStream != null) {
      final chunks = await requestStream.toList();
      lastBody = utf8.decode(chunks.expand((c) => c).toList());
    }
    final encoded = body is String ? body as String : jsonEncode(body ?? {});
    return ResponseBody.fromString(
      encoded,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Dio dio;
  late JsonAdapter adapter;
  late EventPipelineAlignApi api;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'kiosk_code': 'KIOSK1',
      'event_code': 'GALA',
    });
    EventManager.resetCacheForTests();
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    adapter = JsonAdapter();
    dio.httpClientAdapter = adapter;
    api = EventPipelineAlignApi(
      dio: dio,
      events: EventManager(),
      kiosks: KioskManager(),
    );
  });

  test('readStats maps the hub counters', () async {
    adapter.body = {
      'stats': {'imported': 4, 'queued': 1, 'done': 9},
      'serverNowMs': 10,
    };
    final stats = await api.readStats();
    expect(stats!.imported, 4);
    expect(stats.queued, 1);
    expect(stats.done, 9);
    expect(adapter.lastPath, '/api/event/pipeline/stats');
  });

  test('align round-trips items', () async {
    adapter.body = {
      'serverNowMs': 50,
      'items': [
        {
          'id': 'mi-9',
          'source': 'ptp',
          'sourceRef': 'r',
          'contentKey': 'ck',
          'stage': 'DONE',
          'createdAtMs': 1,
          'updatedAtMs': 40,
        },
        'skip',
      ],
      'jobs': [
        {
          'id': 'pj-9',
          'kind': 'print',
          'mediaId': 'mi-9',
          'status': 'PENDING',
          'createdAtMs': 1,
          'updatedAtMs': 1,
        },
        3,
      ],
      'stats': {'done': 1},
    };
    final snap = await api.align();
    expect(snap!.items.single.id, 'mi-9');
    expect(snap.jobs.single.id, 'pj-9');
    expect(snap.stats.done, 1);
    expect(adapter.lastPath, '/api/event/pipeline/align');
  });

  test('4xx and transport errors are null', () async {
    adapter.statusCode = 404;
    expect(await api.readStats(), isNull);
    expect(await api.readSnapshot(), isNull);
    adapter.statusCode = 200;
    adapter.throwOnSend = true;
    expect(await api.align(), isNull);
    expect(await api.readSnapshot(), isNull);
    expect(await api.readStats(), isNull);
  });

  test('align 4xx and a missing stats map are null', () async {
    adapter.statusCode = 403;
    expect(await api.align(), isNull);
    adapter.statusCode = 200;
    adapter.body = {'serverNowMs': 1};
    expect(await api.readStats(), isNull);
  });

  test('align snapshot drops non-list collections', () async {
    adapter.body = {
      'serverNowMs': 1,
      'items': 'nope',
      'jobs': 3,
      'stats': {'done': 2},
    };
    final snap = await api.align();
    expect(snap!.items, isEmpty);
    expect(snap.jobs, isEmpty);
    expect(snap.stats.done, 2);
  });

  test('a non-map body is ignored', () async {
    adapter.body = 'nope';
    expect(await api.readStats(), isNull);
    expect(await api.readSnapshot(), isNull);
  });

  test('readSnapshot lists the shared items', () async {
    adapter.body = {
      'serverNowMs': 3,
      'items': [
        {
          'id': 'mi-snap',
          'source': 'ptp',
          'sourceRef': 'r',
          'contentKey': 'ck',
          'stage': 'QUEUED',
          'createdAtMs': 1,
          'updatedAtMs': 2,
        }
      ],
      'jobs': [
        {
          'id': 'pj-1',
          'kind': 'print',
          'mediaId': 'mi-snap',
          'status': 'PENDING',
          'createdAtMs': 1,
          'updatedAtMs': 2,
          'payload': {'copies': 1},
        }
      ],
      'stats': {'queued': 1},
    };
    final snap = await api.readSnapshot();
    expect(snap!.items.single.id, 'mi-snap');
    expect(snap.jobs.single.kind, 'print');
    expect(adapter.lastPath, '/api/event/pipeline/snapshot');
  });

  test('missing kiosk or event code skips the request', () async {
    SharedPreferences.setMockInitialValues({});
    EventManager.resetCacheForTests();
    final bare = EventPipelineAlignApi(
      dio: dio,
      events: EventManager(),
      kiosks: KioskManager(),
    );
    expect(await bare.readStats(), isNull);
    expect(await bare.readSnapshot(), isNull);
    expect(await bare.align(), isNull);
    expect(adapter.lastPath, isNull);
  });

  test('aligner writes remote rows into the local replica', () async {
    final dir = await Directory.systemTemp.createTemp('fz_align_');
    final db = (await EventPipelineDb.open(dir))!;
    final ledger = EventPipelineLedger(db: db);
    adapter.body = {
      'serverNowMs': 88,
      'items': [
        {
          'id': 'mi-remote',
          'source': 'ptp',
          'sourceRef': 'cam:1',
          'contentKey': 'ck-r',
          'stage': 'QUEUED',
          'createdAtMs': 1,
          'updatedAtMs': 88,
        }
      ],
      'jobs': [],
      'stats': {'queued': 1},
    };
    final stats = await EventPipelineAligner(api: api, ledger: ledger).align();
    expect(stats!.queued, 1);
    expect((await ledger.findById('mi-remote'))!.stage, MediaStage.queued);
    await db.close();
    await dir.delete(recursive: true);
  });

  test('aligner pushes local replica rows for the bound event', () async {
    SharedPreferences.setMockInitialValues({
      'kiosk_code': 'KIOSK1',
      'event_code': 'GALA',
      'event_id': 'EVT1',
    });
    EventManager.resetCacheForTests();
    final dir = await Directory.systemTemp.createTemp('fz_align_push_');
    final db = (await EventPipelineDb.open(dir))!;
    final ledger = EventPipelineLedger(db: db, newId: () => 'mi-local');
    await ledger.insertIfNew(
      source: MediaSource.ptp,
      sourceRef: 'cam:9',
      contentKey: 'ck-local',
      eventId: 'EVT1',
    );
    adapter.body = {
      'serverNowMs': 12,
      'items': <Object>[],
      'jobs': <Object>[],
      'stats': <String, int>{},
    };
    await EventPipelineAligner(api: api, ledger: ledger).align();
    expect(adapter.lastBody, contains('mi-local'));
    await db.close();
    await dir.delete(recursive: true);
  });

  test('aligner readStats returns remote counters', () async {
    adapter.body = {
      'stats': {'failed': 2},
      'serverNowMs': 1,
    };
    final stats = await EventPipelineAligner(api: api).readStats();
    expect(stats!.failed, 2);
  });

  test('aligner returns null when the link is down', () async {
    adapter.throwOnSend = true;
    expect(await EventPipelineAligner(api: api).align(), isNull);
    expect(await EventPipelineAligner(api: api).readStats(), isNull);
  });

  test('aligner swallows a closed replica', () async {
    SharedPreferences.setMockInitialValues({
      'kiosk_code': 'KIOSK1',
      'event_code': 'GALA',
      'event_id': 'EVT1',
    });
    EventManager.resetCacheForTests();
    final dir = await Directory.systemTemp.createTemp('fz_align_closed_');
    final db = (await EventPipelineDb.open(dir))!;
    final ledger = EventPipelineLedger(db: db);
    await db.close();
    expect(await EventPipelineAligner(api: api, ledger: ledger).align(), isNull);
    await dir.delete(recursive: true);
  });

  test('aligner writes the cursor and skips a zero server clock', () async {
    adapter.body = {
      'serverNowMs': 77,
      'items': <Object>[],
      'jobs': <Object>[],
      'stats': <String, int>{},
    };
    await EventPipelineAligner(api: api).align();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('evp_align_since_ms'), 77);

    adapter.body = {
      'serverNowMs': 0,
      'items': <Object>[],
      'jobs': <Object>[],
      'stats': <String, int>{},
    };
    await EventPipelineAligner(api: api).align();
    expect(prefs.getInt('evp_align_since_ms'), 77);
  });

  test('aligner writes remote jobs into the local replica', () async {
    final dir = await Directory.systemTemp.createTemp('fz_align_jobs_');
    final db = (await EventPipelineDb.open(dir))!;
    final queue = EventPipelineQueue(db: db);
    adapter.body = {
      'serverNowMs': 9,
      'items': <Object>[],
      'jobs': [
        {
          'id': 'pj-remote',
          'kind': 'print',
          'mediaId': 'mi-1',
          'status': 'PENDING',
          'createdAtMs': 1,
          'updatedAtMs': 9,
          'payload': {'copies': 2},
        }
      ],
      'stats': <String, int>{},
    };
    await EventPipelineAligner(api: api, queue: queue).align();
    expect((await queue.findById('pj-remote'))!.payload['copies'], 2);
    await db.close();
    await dir.delete(recursive: true);
  });

  test('stats reader falls back to the shared ledger', () async {
    EventPipelineStatsReader.resetSharedForTests();
    adapter.body = {
      'stats': {'imported': 5, 'printPaused': true},
      'serverNowMs': 1,
    };
    final stats = await EventPipelineStatsReader(
      openDb: () async => null,
      alignApi: api,
    ).read();
    expect(stats.imported, 5);
    expect(stats.printPaused, isTrue);
    EventPipelineStatsReader.resetSharedForTests();
  });

  test('stats reader treats a downed link as empty', () async {
    EventPipelineStatsReader.resetSharedForTests();
    adapter.throwOnSend = true;
    final stats = await EventPipelineStatsReader(
      openDb: () async => null,
      alignApi: api,
    ).read();
    expect(stats.isEmpty, isTrue);
    EventPipelineStatsReader.resetSharedForTests();
  });

  test('an operator console lists the shared snapshot', () async {
    EventPipelineConfig.resetCacheForTests();
    EventPipelineRunner.resetInstanceForTests();
    adapter.body = {
      'serverNowMs': 1,
      'items': [
        {
          'id': 'mi-web',
          'source': 'ptp',
          'sourceRef': 'cam:1',
          'contentKey': 'ck-w',
          'stage': 'QUEUED',
          'createdAtMs': 1,
          'updatedAtMs': 1,
        },
        {
          'id': 'mi-ai',
          'source': 'sdcard',
          'sourceRef': 'card:1',
          'contentKey': 'ck-a',
          'stage': 'AI',
          'createdAtMs': 1,
          'updatedAtMs': 1,
        }
      ],
      'jobs': <Object>[],
      'stats': {'queued': 1, 'ai': 1},
    };
    final runner = EventPipelineRunner(
      config: EventPipelineConfig(),
      openDb: () async => null,
    );
    final vm = EventQueueViewModel(
      runner: runner,
      alignApi: api,
      initialFilter: QueueFilter.working,
      refreshInterval: const Duration(days: 1),
    );
    await vm.start();
    expect(vm.entries.single.item.id, 'mi-ai');
    expect(vm.stats.ai, 1);
    vm.dispose();
    runner.stop();
    EventPipelineRunner.resetInstanceForTests();
  });

  test('an operator console pages the shared snapshot', () async {
    EventPipelineConfig.resetCacheForTests();
    EventPipelineRunner.resetInstanceForTests();
    adapter.body = {
      'serverNowMs': 1,
      'items': [
        {
          'id': 'mi-1',
          'source': 'ptp',
          'sourceRef': 'a',
          'contentKey': 'k1',
          'stage': 'QUEUED',
          'createdAtMs': 1,
          'updatedAtMs': 1,
        },
        {
          'id': 'mi-2',
          'source': 'ptp',
          'sourceRef': 'b',
          'contentKey': 'k2',
          'stage': 'QUEUED',
          'createdAtMs': 1,
          'updatedAtMs': 1,
        }
      ],
      'jobs': <Object>[],
      'stats': {'queued': 2},
    };
    final runner = EventPipelineRunner(
      config: EventPipelineConfig(),
      openDb: () async => null,
    );
    final vm = EventQueueViewModel(
      runner: runner,
      alignApi: api,
      pageSize: 1,
      refreshInterval: const Duration(days: 1),
    );
    await vm.start();
    expect(vm.entries.single.item.id, 'mi-1');
    expect(vm.hasMore, isTrue);
    await vm.loadMore();
    expect(vm.entries.map((e) => e.item.id), ['mi-1', 'mi-2']);
    vm.dispose();
    runner.stop();
    EventPipelineRunner.resetInstanceForTests();
  });

  test('an operator console lists an empty queue when the link is down',
      () async {
    EventPipelineConfig.resetCacheForTests();
    EventPipelineRunner.resetInstanceForTests();
    adapter.throwOnSend = true;
    final runner = EventPipelineRunner(
      config: EventPipelineConfig(),
      openDb: () async => null,
    );
    final vm = EventQueueViewModel(
      runner: runner,
      alignApi: api,
      refreshInterval: const Duration(days: 1),
    );
    await vm.start();
    expect(vm.entries, isEmpty);
    vm.dispose();
    runner.stop();
    EventPipelineRunner.resetInstanceForTests();
  });
}
