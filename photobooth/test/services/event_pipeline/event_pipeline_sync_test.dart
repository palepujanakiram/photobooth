import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_info_model.dart';
import 'package:photobooth/models/event_pipeline/event_frame.dart';
import 'package:photobooth/models/kiosk_frame_model.dart';
import 'package:photobooth/services/api_service.dart';
import 'package:photobooth/services/event_manager.dart';
import 'package:photobooth/services/event_pipeline/event_frame_cache.dart';
import 'package:photobooth/services/event_pipeline/event_media_store.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_db.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_config.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_dev_config.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The shape `/api/event/by-code/:code` returns today (screens spec §12): the
/// catalogue arrives as lists, and neither `themeId` nor `frameId` is present.
Map<String, dynamic> backendBody({
  Map<String, dynamic> extra = const <String, dynamic>{},
}) {
  return <String, dynamic>{
    'id': 'evt-1',
    'code': 'GALA-01',
    'name': 'Priya & Arjun',
    'photoMode': 'BOTH',
    'themeCount': 2,
    'themeIds': ['theme-a', 'theme-b'],
    'frameCount': 1,
    'frameIds': ['frame-a'],
    ...extra,
  };
}

/// Manual fake by subclass-and-override, per the repo convention.
class FakeApiService extends ApiService {
  FakeApiService({this.frames = const []});

  List<KioskFrameModel> frames;

  @override
  Future<List<KioskFrameModel>> getKioskFrames() async => frames;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EventPipelineConfig config;
  late EventManager events;
  var clock = 1700000000000;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    EventPipelineConfig.resetCacheForTests();
    EventManager.resetCacheForTests();
    config = EventPipelineConfig();
    events = EventManager();
    clock = 1700000000000;
    await events.setEventCode('GALA-01');
  });

  EventPipelineSync build({
    Future<Map<String, dynamic>?> Function(String code)? fetchEvent,
  }) {
    return EventPipelineSync(
      config: config,
      events: events,
      fetchEvent: fetchEvent ?? (_) async => backendBody(),
      nowMs: () => clock,
    );
  }

  group('sync succeeds', () {
    test('caches the flags and stamps the time', () async {
      final status = await build().sync();

      expect(status.state, EventSyncState.synced);
      expect(status.hasSyncedOnce, isTrue);
      expect(status.syncedAtMs, clock);
      expect(status.error, isNull);
      expect(await config.readSyncedAtMs('GALA-01'), clock);
      expect(await config.hasSyncedOnce('GALA-01'), isTrue);
    });

    test('the code is upper-cased on the way in and out', () async {
      await events.setEventCode('gala-01');
      await build().sync();
      expect(await config.hasSyncedOnce('GALA-01'), isTrue);
    });

    test('backend flags reach the resolved settings', () async {
      await build(
        fetchEvent: (_) async => backendBody(extra: {
          'pipelineEnabled': true,
          'autoPrint': false,
          'defaultCopies': 3,
          'printSize': 's6x8',
        }),
      ).sync();

      final settings = await config.resolve();
      expect(settings.pipelineEnabled, isTrue);
      expect(settings.autoPrint, isFalse);
      expect(settings.defaultCopies, 3);
      expect(settings.printSize, 's6x8');
    });

    test('a nested event object is read the same way', () async {
      await build(
        fetchEvent: (_) async => <String, dynamic>{
          'event': backendBody(extra: {'aiEnabled': false}),
        },
      ).sync();
      expect((await config.resolve()).aiEnabled, isFalse);
    });

    test('a re-sync overwrites rather than merging with the old flags',
        () async {
      await build(
        fetchEvent: (_) async => backendBody(extra: {'defaultCopies': 4}),
      ).sync();
      expect((await config.resolve()).defaultCopies, 4);

      clock += 60000;
      await build(fetchEvent: (_) async => backendBody()).sync();

      final settings = await config.resolve();
      expect(settings.defaultCopies, 1, reason: 'the backend dropped it');
      expect(await config.readSyncedAtMs('GALA-01'), clock);
    });
  });

  group('sync fails', () {
    test('with a cache, the event runs on it and says so', () async {
      await build().sync();
      final syncedAt = await config.readSyncedAtMs('GALA-01');

      clock += 3600000;
      final status = await build(fetchEvent: (_) async => null).sync();

      expect(status.state, EventSyncState.usingCache);
      expect(status.hasSyncedOnce, isTrue,
          reason: 'a cached event still has a chain to freeze');
      expect(status.isFresh, isFalse);
      expect(status.syncedAtMs, syncedAt,
          reason: 'the timestamp is when settings arrived, not when we tried');
      expect(status.error, contains('last synced settings'));
    });

    test('with no cache, import stays blocked and the hub can say why',
        () async {
      final status = await build(fetchEvent: (_) async => null).sync();

      expect(status.state, EventSyncState.never);
      expect(status.hasSyncedOnce, isFalse);
      expect(status.syncedAtMs, isNull);
      expect(status.error, contains('GALA-01'));
      expect(await config.hasSyncedOnce('GALA-01'), isFalse);
    });

    test('no event bound is reported rather than silently succeeding',
        () async {
      await events.setEventCode(null);
      final status = await build().sync();
      expect(status.state, EventSyncState.never);
      expect(status.error, 'No event is bound.');
    });
  });

  group('status without a fetch', () {
    test('an unsynced event reads as never', () async {
      final status = await build().status();
      expect(status.state, EventSyncState.never);
      expect(status.eventCode, 'GALA-01');
    });

    test('a synced event reads from the cache with its timestamp', () async {
      await build().sync();
      final status = await build().status();
      expect(status.state, EventSyncState.usingCache);
      expect(status.syncedAtMs, clock);
      expect(status.syncedAt, DateTime.fromMillisecondsSinceEpoch(clock));
    });

    test('another event does not inherit this one\'s sync', () async {
      await build().sync();
      await events.setEventCode('WEDDING-02');

      final status = await build().status();
      expect(status.state, EventSyncState.never,
          reason: 'settings this device has never seen must block import');
    });

    test('no event bound reads as never', () async {
      await events.setEventCode(null);
      expect((await build().status()).state, EventSyncState.never);
    });
  });

  group('dev scaffold for the two missing ids', () {
    test('fills themeId and frameId from the catalogue the backend does send',
        () async {
      await build().sync();
      final settings = await config.resolve();
      expect(settings.themeId, 'theme-a');
      expect(settings.frameId, 'frame-a');
    });

    test('a real backend value is never overwritten by the fallback', () async {
      await build(
        fetchEvent: (_) async => backendBody(extra: {
          'themeId': 'theme-chosen',
          'frameId': 'frame-chosen',
        }),
      ).sync();

      final settings = await config.resolve();
      expect(settings.themeId, 'theme-chosen');
      expect(settings.frameId, 'frame-chosen');
    });

    test('an empty catalogue leaves the id unset, dropping the step', () async {
      await build(
        fetchEvent: (_) async => <String, dynamic>{
          'id': 'evt-1',
          'code': 'GALA-01',
          'aiEnabled': true,
          'frameEnabled': true,
        },
      ).sync();

      final settings = await config.resolve();
      expect(settings.themeId, isNull);
      expect(settings.canRunAi, isFalse,
          reason: 'AI with no theme to run it under is dropped, not guessed');
      expect(settings.canRunFrame, isFalse);
      expect(settings.resolveSteps(), isNot(contains('ai')));
    });
  });

  group('frame warming', () {
    late Directory root;
    late Directory mediaDir;
    late EventPipelineDb db;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('fz_evp_sync_');
      mediaDir = Directory('${root.path}/media')..createSync(recursive: true);
      db = (await EventPipelineDb.open(root))!;
      // Puts an event id on the device, which is what frame rows are keyed by.
      await events.cacheVerifyResult(
        const EventInfoModel(id: 'evt-1', code: 'GALA-01'),
      );
    });

    tearDown(() async {
      await db.close();
      if (await root.exists()) await root.delete(recursive: true);
    });

    EventFrameCache cache({List<KioskFrameModel> frames = const []}) {
      return EventFrameCache(
        db: db,
        mediaStore: EventMediaStore(resolveDirectory: () async => mediaDir),
        api: FakeApiService(frames: frames),
        fetchBytes: (_) async => Uint8List.fromList(List<int>.filled(64, 1)),
        nowMs: () => 42,
      );
    }

    test('a successful sync downloads the overlays so framing works offline',
        () async {
      final sync = EventPipelineSync(
        config: config,
        events: events,
        fetchEvent: (_) async => backendBody(),
        frameCache: () async => cache(frames: const [
          KioskFrameModel(
            id: 'frame-a',
            name: 'Feriya y Fiesta',
            overlayUrl: 'https://example.test/frame-a.png',
          ),
        ]),
        nowMs: () => clock,
      );

      final status = await sync.sync();

      expect(status.state, EventSyncState.synced);
      expect(status.frames, isNotNull);
      expect(status.frames!.cached, 1);
      expect(status.frames!.selectedIsCached, isTrue,
          reason: 'the frame the chain names is the one that matters');
    });

    test('a frame that will not download is a warning, not a failed sync',
        () async {
      final sync = EventPipelineSync(
        config: config,
        events: events,
        fetchEvent: (_) async => backendBody(),
        frameCache: () async => throw StateError('no store'),
        nowMs: () => clock,
      );

      final status = await sync.sync();
      expect(status.state, EventSyncState.synced);
      expect(status.frames, isNull);
      expect(await config.hasSyncedOnce('GALA-01'), isTrue);
    });

    test('a never-synced event does not go looking for frames', () async {
      var asked = false;
      final sync = EventPipelineSync(
        config: config,
        events: events,
        fetchEvent: (_) async => null,
        frameCache: () async {
          asked = true;
          return null;
        },
        nowMs: () => clock,
      );

      expect((await sync.sync()).state, EventSyncState.never);
      expect(asked, isFalse);
    });
  });

  group('production defaults', () {
    test('a sync built with nothing injected still reports honestly', () async {
      // Exercises the production fallbacks. No event is bound, so this answers
      // from prefs alone and never reaches for the network.
      await events.setEventCode(null);
      final status = await EventPipelineSync().status();
      expect(status.state, EventSyncState.never);
      expect(status.error, 'No event is bound.');
    });

    test('with no frame cache and no clock injected it still syncs', () async {
      // The production defaults: real wall clock, and no database to record a
      // frame cache in, which is what a device with unavailable storage has.
      await events.cacheVerifyResult(
        const EventInfoModel(id: 'evt-1', code: 'GALA-01'),
      );
      final before = DateTime.now().millisecondsSinceEpoch;
      final status = await EventPipelineSync(
        config: config,
        events: events,
        fetchEvent: (_) async => backendBody(),
      ).sync();

      expect(status.state, EventSyncState.synced);
      expect(status.frames, isNull);
      expect(status.syncedAtMs, greaterThanOrEqualTo(before));
    });

    test('copyWith keeps the frames it already had', () {
      const original = EventSyncStatus(
        state: EventSyncState.synced,
        eventCode: 'GALA-01',
        syncedAtMs: 42,
        frames: FrameCacheStatus(total: 1, cached: 1, selectedIsCached: true),
        error: 'kept',
      );
      final copy = original.copyWith();
      expect(copy.frames, same(original.frames));
      expect(copy.error, 'kept');
      expect(copy.syncedAtMs, 42);
    });
  });

  group('EventPipelineDevConfig', () {
    test('backend beats override beats catalogue', () {
      expect(
        EventPipelineDevConfig.resolveThemeId(
          fromBackend: 'from-backend',
          catalogue: const ['from-catalogue'],
        ),
        'from-backend',
      );
      expect(
        EventPipelineDevConfig.resolveFrameId(
          fromBackend: '  ',
          catalogue: const ['from-catalogue'],
        ),
        'from-catalogue',
      );
    });

    test('blank catalogue entries are skipped', () {
      expect(
        EventPipelineDevConfig.resolveThemeId(
          catalogue: const ['', '  ', 'real'],
        ),
        'real',
      );
    });

    test('nothing anywhere resolves to null', () {
      expect(EventPipelineDevConfig.resolveFrameId(), isNull);
    });
  });
}
