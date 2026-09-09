import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_info_model.dart';
import 'package:photobooth/models/event_pipeline/event_pipeline_flags.dart';
import 'package:photobooth/screens/event_pipeline/event_settings_viewmodel.dart';
import 'package:photobooth/services/event_manager.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_config.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_db.dart';
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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    EventPipelineConfig.resetCacheForTests();
    EventManager.resetCacheForTests();
    root = await Directory.systemTemp.createTemp('fz_evp_settings_');
    db = (await EventPipelineDb.open(root))!;
    config = EventPipelineConfig();
    events = EventManager();
    await events.cacheVerifyResult(
      const EventInfoModel(id: 'EVT1', code: 'GALA-01'),
    );
  });

  tearDown(() async {
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  EventSettingsViewModel build({EventSyncStatus? status}) {
    return EventSettingsViewModel(
      config: config,
      events: events,
      sync: FakeSync(result: status ?? synced),
      openDb: () async => db,
    );
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
}
