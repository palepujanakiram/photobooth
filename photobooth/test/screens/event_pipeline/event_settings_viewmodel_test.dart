import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_info_model.dart';
import 'package:photobooth/models/event_pipeline/event_pipeline_flags.dart';
import 'package:photobooth/models/event_pipeline/media_rendition.dart';
import 'package:photobooth/screens/event_pipeline/event_settings_viewmodel.dart';
import 'package:photobooth/services/event_manager.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_config.dart';
import 'package:photobooth/models/event_pipeline/media_item.dart';
import 'package:photobooth/services/event_pipeline/event_media_store.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_db.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_ledger.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_queue.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_runner.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeSync extends EventPipelineSync {
  FakeSync({required this.result});

  EventSyncStatus result;
  int calls = 0;

  @override
  Future<EventSyncStatus> status() async => result;

  @override
  Future<EventSyncStatus> sync() async {
    calls++;
    return result;
  }
}

const synced = EventSyncStatus(
  state: EventSyncState.synced,
  eventCode: 'GALA-01',
  syncedAtMs: 1757408520000, // 9 Sep 2026, 09:22 local in the test's zone
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late EventPipelineDb db;
  late EventPipelineConfig config;
  late EventManager events;
  late EventMediaStore media;
  late EventPipelineRunner runner;
  var ids = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    EventPipelineConfig.resetCacheForTests();
    EventPipelineRunner.resetInstanceForTests();
    EventManager.resetCacheForTests();
    root = await Directory.systemTemp.createTemp('fz_evp_settings_');
    ids = 0;
    db = (await EventPipelineDb.open(root))!;
    media = EventMediaStore(
      resolveDirectory: () async =>
          Directory('${root.path}/media')..createSync(recursive: true),
    );
    config = EventPipelineConfig();
    events = EventManager();
    runner = EventPipelineRunner(
      config: config,
      mediaStore: media,
      openDb: () async => db,
    );
    await events.cacheVerifyResult(
      const EventInfoModel(id: 'EVT1', code: 'GALA-01'),
    );
    // The runner refuses to wire itself with the pipeline off, so the flag has
    // to be cached before it starts; individual tests then cache their own.
    await config.cacheFlags(const EventPipelineFlags(pipelineEnabled: true));
    await runner.ensureStarted();
  });

  tearDown(() async {
    runner.stop();
    EventPipelineRunner.resetInstanceForTests();
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  EventSettingsViewModel build({EventSyncStatus? status}) {
    return EventSettingsViewModel(
      config: config,
      events: events,
      sync: FakeSync(result: status ?? synced),
      runner: runner,
      openDb: () async => db,
    );
  }

  Future<String> seedItem({String stage = MediaStage.done}) async {
    final ledger = EventPipelineLedger(db: db, newId: () => 'm${ids++}');
    final r = await ledger.insertIfNew(
      source: MediaSource.sdCard,
      sourceRef: 'V:$ids',
      contentKey: 'ck$ids',
      eventId: 'EVT1',
    );
    await media.putBytes('EVT1/${r.item.id}-source.jpg', [1, 2, 3]);
    await ledger.putRendition(MediaRendition(
      mediaId: r.item.id,
      kind: RenditionKind.source,
      path: 'EVT1/${r.item.id}-source.jpg',
      createdAtMs: 1,
    ));
    if (stage != MediaStage.ingested) await ledger.setStage(r.item.id, stage);
    return r.item.id;
  }

  Future<void> cache(EventPipelineFlags flags) => config.cacheFlags(flags);

  group('rows', () {
    test('every setting carries one line saying what it does', () async {
      await cache(const EventPipelineFlags(
        pipelineEnabled: true,
        aiEnabled: true,
        themeId: 'theme-a',
        frameEnabled: true,
        frameId: 'frame-a',
        autoPrint: true,
        defaultCopies: 2,
        printSize: 's6x8',
      ));
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      // Read by an operator under time pressure who did not configure the
      // event; a bare toggle would not tell them what turning it off does.
      expect(vm.rows, hasLength(5));
      for (final row in vm.rows) {
        expect(row.subtitle, isNotEmpty, reason: row.label);
      }
    });

    test('values read off the synced config', () async {
      await cache(const EventPipelineFlags(
        pipelineEnabled: true,
        aiEnabled: true,
        themeId: 'theme-a',
        frameEnabled: false,
        autoPrint: false,
        defaultCopies: 3,
        printSize: 's5x7',
      ));
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      final byLabel = {for (final r in vm.rows) r.label: r};
      expect(byLabel['AI generation']!.value, 'on');
      expect(byLabel['AI generation']!.detail, 'Theme · theme-a');
      expect(byLabel['Apply frame']!.value, 'off');
      expect(byLabel['Auto print']!.value, 'off');
      expect(byLabel['Copies per photo']!.value, '3');
      expect(byLabel['Print size']!.value, 's5x7');
    });

    test('AI on with no theme warns that the step will be skipped', () async {
      await cache(const EventPipelineFlags(
        pipelineEnabled: true,
        aiEnabled: true,
      ));
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      final ai = vm.rows.firstWhere((r) => r.label == 'AI generation');
      expect(ai.warning, contains('skipped'));
    });

    test('framing on with no artwork warns it cannot run offline', () async {
      await cache(const EventPipelineFlags(
        pipelineEnabled: true,
        frameEnabled: true,
        frameId: 'frame-a',
      ));
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      final frame = vm.rows.firstWhere((r) => r.label == 'Apply frame');
      expect(frame.warning, contains('offline'));
      expect(vm.needsFrameDownload, isTrue);
    });

    test('framing off never asks for a download', () async {
      await cache(const EventPipelineFlags(pipelineEnabled: true));
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.needsFrameDownload, isFalse);
    });
  });

  group('chain preview', () {
    test('says plainly what each photo will run', () async {
      await cache(const EventPipelineFlags(
        pipelineEnabled: true,
        aiEnabled: true,
        themeId: 't',
        frameEnabled: true,
        frameId: 'f',
        autoPrint: true,
        defaultCopies: 2,
        printSize: 's4x6',
      ));
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.chainSummary, 'AI → Frame → Print s4x6 · 2 copies');
    });

    test('an event that runs nothing says so', () async {
      await cache(const EventPipelineFlags(
        pipelineEnabled: true,
        aiEnabled: false,
        frameEnabled: false,
        autoPrint: false,
      ));
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.chainSummary, 'Nothing will run — imports are stored only.');
    });
  });

  group('sync', () {
    test('is the only control, and re-fetches on demand', () async {
      await cache(const EventPipelineFlags(pipelineEnabled: true));
      final sync = FakeSync(result: synced);
      final vm = EventSettingsViewModel(
        config: config,
        events: events,
        sync: sync,
        openDb: () async => db,
      );
      await vm.start();
      addTearDown(vm.dispose);
      expect(sync.calls, 0, reason: 'opening the screen must not fetch');

      await vm.sync();
      expect(sync.calls, 1);
      expect(vm.syncStatus.state, EventSyncState.synced);
    });

    test('shows the same timestamp the hub does', () async {
      await cache(const EventPipelineFlags(pipelineEnabled: true));
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.syncedLabel, startsWith('Synced from ZenAI · '));
    });

    test('a device that never synced says so rather than inventing a date',
        () async {
      final vm = build(status: const EventSyncStatus.never());
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.syncedLabel, 'Never synced');
    });
  });

  group('frame preview', () {
    test('there is nothing to view before the artwork is cached', () async {
      await cache(const EventPipelineFlags(
        pipelineEnabled: true,
        frameEnabled: true,
        frameId: 'frame-a',
      ));
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.canPreviewFrame, isFalse);
      expect(vm.frameImage, isNull);
    });

    test('an event with no frame configured offers no preview', () async {
      await cache(const EventPipelineFlags(pipelineEnabled: true));
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.canPreviewFrame, isFalse);
    });
  });

  group('frame download', () {
    test('downloads the artwork on demand and clears the warning', () async {
      await cache(const EventPipelineFlags(
        pipelineEnabled: true,
        frameEnabled: true,
        frameId: 'frame-a',
      ));
      final vm = EventSettingsViewModel(
        config: config,
        events: events,
        sync: FakeSync(result: synced),
        openDb: () async => db,
      );
      await vm.start();
      addTearDown(vm.dispose);
      expect(vm.needsFrameDownload, isTrue);

      // The row doubles as the fix for the hub's "frames not cached" warning.
      await vm.downloadFrames();

      expect(vm.isDownloadingFrames, isFalse);
    });
  });

  group('leaving the event', () {
    test('unbinds the device but leaves the photos alone', () async {
      await cache(const EventPipelineFlags(pipelineEnabled: true));
      final id = await seedItem();
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      await vm.leaveEvent();

      expect(await events.getEventCode(), isNull);
      // Stepping out of an event, or handing the tablet on, must not destroy a
      // night's work.
      final ledger = EventPipelineLedger(db: db);
      expect(await ledger.findById(id), isNotNull);
      expect(await media.getFile('EVT1/$id-source.jpg'), isNotNull);
    });

    test('the cached settings go with the binding', () async {
      await cache(const EventPipelineFlags(pipelineEnabled: true));
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      await vm.leaveEvent();
      expect((await config.readCachedFlags()).isEmpty, isTrue);
    });
  });

  group('clearing event data', () {
    test('deletes the rows and the files, and reports how many', () async {
      await cache(const EventPipelineFlags(pipelineEnabled: true));
      final a = await seedItem();
      final b = await seedItem();
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      final removed = await vm.clearEventData();

      expect(removed, 2);
      final ledger = EventPipelineLedger(db: db);
      expect(await ledger.findById(a), isNull);
      expect(await ledger.findById(b), isNull);
      expect(await media.getFile('EVT1/$a-source.jpg'), isNull);
    });

    test('takes the jobs with it', () async {
      await cache(const EventPipelineFlags(pipelineEnabled: true));
      final id = await seedItem();
      final queue = EventPipelineQueue(db: db);
      await queue.enqueue(kind: 'print', mediaId: id, eventId: 'EVT1');

      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);
      await vm.clearEventData();

      expect(await queue.findFor(kind: 'print', mediaId: id), isNull);
    });

    test("another event's photos are untouched", () async {
      await cache(const EventPipelineFlags(pipelineEnabled: true));
      await seedItem();
      final ledger = EventPipelineLedger(db: db, newId: () => 'other-1');
      final other = await ledger.insertIfNew(
        source: MediaSource.sdCard,
        sourceRef: 'V:other',
        contentKey: 'ck-other',
        eventId: 'OTHER-EVENT',
      );

      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);
      await vm.clearEventData();

      // event_id on every row is exactly what makes this a single delete.
      expect(await ledger.findById(other.item.id), isNotNull);
    });

    test('unfinished work is named rather than silently destroyed', () async {
      await cache(const EventPipelineFlags(pipelineEnabled: true));
      await seedItem(stage: MediaStage.printing);
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.purgeBlockers, hasLength(1));
      expect(vm.purgeBlockers.single, contains('not finished'));
    });

    test('a finished event has nothing to warn about', () async {
      await cache(const EventPipelineFlags(pipelineEnabled: true));
      await seedItem();
      await seedItem(stage: MediaStage.failed);
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.purgeBlockers, isEmpty);
    });

    test('clearing with no event bound is harmless', () async {
      await cache(const EventPipelineFlags(pipelineEnabled: true));
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);
      await events.clearEvent();

      expect(await vm.clearEventData(), 0);
    });
  });
}
