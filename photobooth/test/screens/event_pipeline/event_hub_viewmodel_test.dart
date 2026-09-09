import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_info_model.dart';
import 'package:photobooth/models/event_pipeline/event_pipeline_flags.dart';
import 'package:photobooth/models/event_pipeline/event_readiness.dart';
import 'package:photobooth/models/event_pipeline/media_item.dart';
import 'package:photobooth/models/event_pipeline/printer_consumables.dart';
import 'package:photobooth/screens/event_pipeline/event_hub_viewmodel.dart';
import 'package:photobooth/services/direct_ptp_camera_service.dart';
import 'package:photobooth/services/event_manager.dart';
import 'package:photobooth/services/event_pipeline/event_media_store.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_config.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_db.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_ledger.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_queue.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_runner.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_stats.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_sync.dart';
import 'package:photobooth/services/event_pipeline/ingest/event_storage_channel.dart';
import 'package:photobooth/services/event_pipeline/printer_status_reader.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int gb = 1024 * 1024 * 1024;

/// Manual fakes by subclass-and-override, per the repo convention.
class FakePrinterStatusReader extends PrinterStatusReader {
  FakePrinterStatusReader({this.consumables = PrinterConsumables.unknown});

  PrinterConsumables consumables;

  @override
  Future<PrinterConsumables> read() async => consumables;
}

class FakeStorageChannel extends EventStorageChannel {
  FakeStorageChannel({this.free = 46 * gb, this.shouldThrow = false});

  int? free;
  bool shouldThrow;

  @override
  Future<int?> freeBytes(String path) async {
    if (shouldThrow) throw StateError('volume gone');
    return free;
  }
}

class FakeCamera extends DirectPtpCameraService {
  FakeCamera({this.device, this.shouldThrow = false});

  DirectPtpDevice? device;
  bool shouldThrow;

  @override
  Future<DirectPtpDevice?> probeDevice() async {
    if (shouldThrow) throw StateError('usb host unavailable');
    return device;
  }
}

class FakeSync extends EventPipelineSync {
  FakeSync({required this.initial, EventSyncStatus? afterSync})
      : afterSync = afterSync ?? initial;

  EventSyncStatus initial;
  EventSyncStatus afterSync;
  int syncCalls = 0;

  @override
  Future<EventSyncStatus> status() async => initial;

  @override
  Future<EventSyncStatus> sync() async {
    syncCalls++;
    return afterSync;
  }
}

const synced = EventSyncStatus(
  state: EventSyncState.synced,
  eventCode: 'GALA-01',
  syncedAtMs: 1700000000000,
);

const neverSynced = EventSyncStatus.never();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory mediaDir;
  late EventPipelineDb db;
  late EventPipelineConfig config;
  late EventManager events;
  late FakePrinterStatusReader printer;
  late FakeStorageChannel storage;
  late FakeCamera camera;
  var ids = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    EventPipelineConfig.resetCacheForTests();
    EventPipelineRunner.resetInstanceForTests();
    EventPipelineStatsReader.resetSharedForTests();
    EventManager.resetCacheForTests();
    root = await Directory.systemTemp.createTemp('fz_evp_hub_');
    mediaDir = Directory('${root.path}/media')..createSync(recursive: true);
    db = (await EventPipelineDb.open(root))!;
    ids = 0;
    config = EventPipelineConfig();
    events = EventManager();
    printer = FakePrinterStatusReader(
      consumables: const PrinterConsumables(
        code: 0,
        readiness: PrinterReadiness.ready,
        name: 'DS-RX1',
      ),
    );
    storage = FakeStorageChannel();
    camera = FakeCamera(
      device: const DirectPtpDevice(
        deviceName: '/dev/bus/usb/001/004',
        vendorId: 0x04a9,
        productId: 0x32f0,
        product: 'Canon EOS R',
      ),
    );
    await events.cacheVerifyResult(
      const EventInfoModel(id: 'evt-1', code: 'GALA-01', name: 'Priya & Arjun'),
    );
    // AI off, framing off: "healthy" must mean every row green, so each test
    // can turn exactly one thing amber or red.
    await config.cacheFlags(const EventPipelineFlags(
      pipelineEnabled: true,
      autoPrint: true,
      aiEnabled: false,
      frameEnabled: false,
    ));
  });

  tearDown(() async {
    EventPipelineRunner.resetInstanceForTests();
    EventPipelineStatsReader.resetSharedForTests();
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  EventHubViewModel build({EventSyncStatus? initial, EventSyncStatus? after}) {
    return EventHubViewModel(
      config: config,
      events: events,
      sync: FakeSync(
        initial: initial ?? neverSynced,
        afterSync: after ?? initial ?? neverSynced,
      ),
      stats: EventPipelineStatsReader(openDb: () async => db),
      printer: printer,
      storage: storage,
      mediaStore: EventMediaStore(resolveDirectory: () async => mediaDir),
      camera: camera,
      openDb: () async => db,
      runner: EventPipelineRunner(
        config: config,
        mediaStore: EventMediaStore(resolveDirectory: () async => mediaDir),
        openDb: () async => db,
      ),
      // Long enough that no timer fires inside a test.
      refreshInterval: const Duration(minutes: 5),
    );
  }

  Future<void> seed(String stage) async {
    final ledger = EventPipelineLedger(db: db, newId: () => 'm${ids++}');
    final r = await ledger.insertIfNew(
      source: MediaSource.sdCard,
      sourceRef: 'V:$ids',
      contentKey: 'ck$ids',
      eventId: 'evt-1',
    );
    if (stage != MediaStage.ingested) await ledger.setStage(r.item.id, stage);
  }

  group('start', () {
    test('loads the event and adopts the fetched settings', () async {
      final vm = build(initial: neverSynced, after: synced);
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.eventName, 'Priya & Arjun');
      expect(vm.syncStatus.state, EventSyncState.synced);
      expect(vm.readiness, isNotNull);
      expect(vm.isSyncing, isFalse);
    });

    test('the hub is painted before the fetch lands, not after', () async {
      // §3A: a slow venue link must not leave the operator on a spinner. The
      // readiness block is filled in from the cache first and the sync is
      // reported as another row in it.
      final slow = _SlowSync();
      final vm = EventHubViewModel(
        config: config,
        events: events,
        sync: slow,
        stats: EventPipelineStatsReader(openDb: () async => db),
        printer: printer,
        storage: storage,
        mediaStore: EventMediaStore(resolveDirectory: () async => mediaDir),
        camera: camera,
        openDb: () async => db,
        runner: EventPipelineRunner(
          config: config,
          mediaStore: EventMediaStore(resolveDirectory: () async => mediaDir),
          openDb: () async => db,
        ),
        refreshInterval: const Duration(minutes: 5),
      );
      final starting = vm.start();
      addTearDown(vm.dispose);

      // The fetch has not answered yet, but the block is already filled in.
      await _until(() => vm.readinessRows.isNotEmpty);
      expect(vm.readinessRows, isNotEmpty,
          reason: 'the block renders on cached state alone');
      expect(vm.eventName, 'Priya & Arjun');
      expect(vm.isSyncing, isTrue);
      expect(vm.canImport, isFalse, reason: 'nothing synced yet');

      slow.completer.complete(synced);
      await starting;
      expect(vm.canImport, isTrue);
    });

    test('starts the pipeline workers', () async {
      final runner = EventPipelineRunner(
        config: config,
        mediaStore: EventMediaStore(resolveDirectory: () async => mediaDir),
        openDb: () async => db,
      );
      final vm = EventHubViewModel(
        config: config,
        events: events,
        sync: FakeSync(initial: synced),
        stats: EventPipelineStatsReader(openDb: () async => db),
        printer: printer,
        storage: storage,
        mediaStore: EventMediaStore(resolveDirectory: () async => mediaDir),
        camera: camera,
        openDb: () async => db,
        runner: runner,
        refreshInterval: const Duration(minutes: 5),
      );
      await vm.start();
      addTearDown(vm.dispose);

      expect(runner.isRunning, isTrue);
    });
  });

  group('readiness', () {
    test('a healthy synced device is ready to run', () async {
      final vm = build(initial: synced);
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.headline, 'READY TO RUN');
      expect(vm.canImport, isTrue);
      expect(vm.canCapture, isTrue);
      expect(vm.readinessRows, hasLength(ReadinessKind.values.length));
    });

    test('import is blocked before the first sync, with the reason', () async {
      final vm = build(initial: neverSynced, after: neverSynced);
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.canImport, isFalse);
      expect(vm.canCapture, isFalse);
      expect(vm.importBlockedReason, EventReadiness.waitingForSettings);
      expect(vm.headline, 'NOT READY');
    });

    test('no camera disables Capture only', () async {
      camera.device = null;
      final vm = build(initial: synced);
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.canCapture, isFalse);
      expect(vm.captureBlockedReason, 'No camera connected');
      expect(vm.canImport, isTrue);
    });

    test('a camera with no product name falls back to the bus path', () async {
      camera.device = const DirectPtpDevice(
        deviceName: '/dev/bus/usb/001/004',
        vendorId: 1,
        productId: 2,
      );
      final vm = build(initial: synced);
      await vm.start();
      addTearDown(vm.dispose);

      final row =
          vm.readinessRows.firstWhere((r) => r.kind == ReadinessKind.camera);
      expect(row.detail, '/dev/bus/usb/001/004');
    });

    test('a full disk blocks import', () async {
      storage.free = 100;
      final vm = build(initial: synced);
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.canImport, isFalse);
      expect(vm.importBlockedReason, 'Not enough free space');
    });

    test('a printer needing attention is surfaced without blocking import',
        () async {
      printer.consumables = const PrinterConsumables(
        code: 1200,
        readiness: PrinterReadiness.needsAttention,
        label: 'Ribbon end — replace ribbon',
      );
      final vm = build(initial: synced);
      await vm.start();
      addTearDown(vm.dispose);

      final row =
          vm.readinessRows.firstWhere((r) => r.kind == ReadinessKind.printer);
      expect(row.tone, ReadinessTone.blocked);
      expect(row.detail, 'Ribbon end — replace ribbon');
      expect(vm.canImport, isTrue);
    });

    test('a camera probe that throws reads as no camera, not a crash',
        () async {
      camera.shouldThrow = true;
      final vm = build(initial: synced);
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.canCapture, isFalse);
      expect(vm.canImport, isTrue);
    });

    test('unreadable free space is a warning, not a blocked import', () async {
      storage.shouldThrow = true;
      final vm = build(initial: synced);
      await vm.start();
      addTearDown(vm.dispose);

      final row =
          vm.readinessRows.firstWhere((r) => r.kind == ReadinessKind.storage);
      expect(row.tone, ReadinessTone.warn);
      expect(vm.canImport, isTrue,
          reason: 'an unreadable disk is not proof it is full');
    });

    test('a frame-enabled event reads the cache to answer the frames row',
        () async {
      await config.cacheFlags(const EventPipelineFlags(
        pipelineEnabled: true,
        autoPrint: true,
        aiEnabled: false,
        frameEnabled: true,
        frameId: 'frame-a',
      ));
      final vm = EventHubViewModel(
        config: config,
        events: events,
        sync: FakeSync(initial: synced),
        stats: EventPipelineStatsReader(openDb: () async => db),
        printer: printer,
        storage: storage,
        mediaStore: EventMediaStore(resolveDirectory: () async => mediaDir),
        camera: camera,
        openDb: () async => db,
        // The runner's own frame warm-up is background work that outlives a
        // test; this exercises the hub's frame read, not the runner's.
        runner: EventPipelineRunner(
          config: config,
          mediaStore: EventMediaStore(resolveDirectory: () async => mediaDir),
          openDb: () async => null,
        ),
        refreshInterval: const Duration(minutes: 5),
      );
      await vm.start();
      addTearDown(vm.dispose);

      final row =
          vm.readinessRows.firstWhere((r) => r.kind == ReadinessKind.frames);
      expect(row.tone, ReadinessTone.blocked,
          reason: 'nothing has been downloaded, so framing cannot run offline');
      expect(vm.settings!.frameEnabled, isTrue);
    });

    test('an unreadable frame cache is a warning, not a crash', () async {
      await config.cacheFlags(const EventPipelineFlags(
        pipelineEnabled: true,
        autoPrint: true,
        aiEnabled: false,
        frameEnabled: true,
        frameId: 'frame-a',
      ));
      // A separate path, so closing it does not take the shared handle with it.
      final other = await Directory.systemTemp.createTemp('fz_evp_hub_shut_');
      addTearDown(() => other.delete(recursive: true));
      final closed = (await EventPipelineDb.open(other))!;
      await closed.close();

      final vm = EventHubViewModel(
        config: config,
        events: events,
        sync: FakeSync(initial: synced),
        stats: EventPipelineStatsReader(openDb: () async => db),
        printer: printer,
        storage: storage,
        mediaStore: EventMediaStore(resolveDirectory: () async => mediaDir),
        camera: camera,
        openDb: () async => closed,
        runner: EventPipelineRunner(
          config: config,
          mediaStore: EventMediaStore(resolveDirectory: () async => mediaDir),
          openDb: () async => null,
        ),
        refreshInterval: const Duration(minutes: 5),
      );
      await vm.start();
      addTearDown(vm.dispose);

      final row =
          vm.readinessRows.firstWhere((r) => r.kind == ReadinessKind.frames);
      expect(row.tone, ReadinessTone.warn);
      expect(row.detail, 'Not checked yet');
    });

    test('the event chrome is exposed for the header', () async {
      await events.cacheVerifyResult(const EventInfoModel(
        id: 'evt-1',
        code: 'GALA-01',
        name: 'Priya & Arjun',
        chrome: EventChrome(tagline: 'Warm peach to purple'),
      ));
      final vm = build(initial: synced);
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.eventName, 'Priya & Arjun');
      expect(vm.eventTagline, 'Warm peach to purple');
    });

    test('before start there is nothing to import into', () {
      final vm = build();
      expect(vm.canImport, isFalse);
      expect(vm.importBlockedReason, EventReadiness.waitingForSettings);
      expect(vm.headline, 'Checking…');
      expect(vm.readinessRows, isEmpty);
    });
  });

  group('queue status', () {
    test('a paused queue is surfaced on the hub, not only in the queue screen',
        () async {
      await seed(MediaStage.framing);
      final vm = build(initial: synced);
      await vm.start();
      addTearDown(vm.dispose);

      expect(
        vm.readinessRows
            .firstWhere((r) => r.kind == ReadinessKind.queue)
            .detail,
        'Processing · 1 in flight',
      );

      await EventPipelineQueue(db: db).setPaused(true);
      await vm.refresh();

      final row =
          vm.readinessRows.firstWhere((r) => r.kind == ReadinessKind.queue);
      expect(row.tone, ReadinessTone.warn);
      expect(row.detail, 'Paused');
    });
  });

  group('counters', () {
    test('read the ledger, not the network', () async {
      await seed(MediaStage.queued);
      await seed(MediaStage.queued);
      await seed(MediaStage.framing);
      await seed(MediaStage.done);
      await seed(MediaStage.failed);

      final vm = build(initial: synced);
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.counters.queued, 2);
      expect(vm.counters.framing, 1);
      expect(vm.counters.done, 1);
      expect(vm.counters.failed, 1);
    });

    test('refresh picks up work that landed since the last tick', () async {
      final vm = build(initial: synced);
      await vm.start();
      addTearDown(vm.dispose);
      expect(vm.counters.done, 0);

      await seed(MediaStage.done);
      await vm.refresh();

      expect(vm.counters.done, 1);
    });
  });

  group('resync', () {
    test('re-fetches and adopts the new status', () async {
      final vm = build(initial: neverSynced, after: synced);
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.syncStatus.state, EventSyncState.synced);
      expect(vm.canImport, isTrue);
    });

    test('a sync that throws leaves the hub standing', () async {
      final vm = EventHubViewModel(
        config: config,
        events: events,
        sync: _ThrowingSync(),
        stats: EventPipelineStatsReader(openDb: () async => db),
        printer: printer,
        storage: storage,
        mediaStore: EventMediaStore(resolveDirectory: () async => mediaDir),
        camera: camera,
        openDb: () async => db,
        runner: EventPipelineRunner(
          config: config,
          mediaStore: EventMediaStore(resolveDirectory: () async => mediaDir),
          openDb: () async => db,
        ),
        refreshInterval: const Duration(minutes: 5),
      );
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.isSyncing, isFalse);
      expect(vm.readiness, isNotNull);
      expect(vm.canImport, isFalse, reason: 'nothing synced, so nothing runs');
    });

    test('a second tap while one is in flight is ignored', () async {
      final sync = FakeSync(initial: synced);
      final vm = EventHubViewModel(
        config: config,
        events: events,
        sync: sync,
        stats: EventPipelineStatsReader(openDb: () async => db),
        printer: printer,
        storage: storage,
        mediaStore: EventMediaStore(resolveDirectory: () async => mediaDir),
        camera: camera,
        openDb: () async => db,
        runner: EventPipelineRunner(
          config: config,
          mediaStore: EventMediaStore(resolveDirectory: () async => mediaDir),
          openDb: () async => db,
        ),
        refreshInterval: const Duration(minutes: 5),
      );
      await vm.start();
      addTearDown(vm.dispose);
      final afterStart = sync.syncCalls;

      await Future.wait([vm.resync(), vm.resync()]);

      expect(sync.syncCalls, afterStart + 1);
    });
  });

  test('the production constructor wires its own collaborators', () {
    // Construction only — nothing here touches a channel or the disk until
    // start() runs, and this is the path the route table actually takes.
    final vm = EventHubViewModel();
    expect(vm.readiness, isNull);
    expect(vm.counters.isEmpty, isTrue);
    expect(vm.syncStatus.state, EventSyncState.never);
    vm.dispose();
  });

  test('dispose stops the timer and later notifications', () async {
    final vm = build(initial: synced);
    await vm.start();
    vm.dispose();
    // Must not call notifyListeners on a disposed model.
    await vm.refresh();
  });
}

/// Waits for [condition], so a test does not depend on how many event-loop
/// turns the local reads happen to take on the machine running it.
Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// A sync that does not answer until the test lets it.
class _SlowSync extends EventPipelineSync {
  final completer = Completer<EventSyncStatus>();

  @override
  Future<EventSyncStatus> status() async => neverSynced;

  @override
  Future<EventSyncStatus> sync() => completer.future;
}

class _ThrowingSync extends EventPipelineSync {
  @override
  Future<EventSyncStatus> status() async => neverSynced;

  @override
  Future<EventSyncStatus> sync() async => throw StateError('boom');
}
