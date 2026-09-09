import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_pipeline/event_pipeline_flags.dart';
import 'package:photobooth/models/event_pipeline/event_print_size.dart';
import 'package:photobooth/models/event_pipeline/media_item.dart';
import 'package:photobooth/services/event_pipeline/event_media_store.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_config.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_db.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_ledger.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_runner.dart';
import 'package:photobooth/services/event_pipeline/frame_compositor.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StubCompositor implements FrameCompositor {
  @override
  Future<CompositeResult> composite({
    required String photoPath,
    required String? framePath,
    required EventPrintSize size,
    int quality = 88,
    int thumbShortSide = 0,
  }) async {
    return CompositeResult(
      bytes: Uint8List.fromList(const [1, 2, 3]),
      width: size.width,
      height: size.height,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory mediaDir;
  late EventPipelineDb db;
  late EventPipelineConfig config;
  late EventPipelineRunner runner;
  var ids = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    EventPipelineConfig.resetCacheForTests();
    EventPipelineRunner.resetInstanceForTests();
    root = await Directory.systemTemp.createTemp('fz_evp_runner_');
    mediaDir = Directory('${root.path}/media')..createSync(recursive: true);
    ids = 0;
    db = (await EventPipelineDb.open(root))!;
    config = EventPipelineConfig();
    runner = EventPipelineRunner(
      config: config,
      mediaStore: EventMediaStore(resolveDirectory: () async => mediaDir),
      compositor: StubCompositor(),
      openDb: () async => db,
    );
  });

  tearDown(() async {
    runner.stop();
    EventPipelineRunner.resetInstanceForTests();
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<String> seedItem() async {
    final ledger = EventPipelineLedger(db: db, newId: () => 'm${ids++}');
    final r = await ledger.insertIfNew(
      source: MediaSource.sdCard,
      sourceRef: 'V:$ids',
      contentKey: 'ck$ids',
      eventId: 'EVT1',
    );
    return r.item.id;
  }

  group('lifecycle', () {
    test('does not start when the pipeline is off', () async {
      expect(await runner.ensureStarted(), isFalse);
      expect(runner.isRunning, isFalse);
      expect(EventPipelineRunner.instance, isNull);
    });

    test('starts when the pipeline is on', () async {
      await config.cacheFlags(
          const EventPipelineFlags(pipelineEnabled: true));
      expect(await runner.ensureStarted(), isTrue);
      expect(runner.isRunning, isTrue);
      expect(EventPipelineRunner.instance, same(runner));
    });

    test('is idempotent — re-entering a station does not stack timers', () async {
      await config.cacheFlags(
          const EventPipelineFlags(pipelineEnabled: true));
      await runner.ensureStarted();
      final queue = runner.queue;
      await runner.ensureStarted();
      expect(runner.queue, same(queue), reason: 'wired once, not twice');
    });

    test('turning the setting off stops the workers without a restart',
        () async {
      await config.cacheFlags(
          const EventPipelineFlags(pipelineEnabled: true));
      await runner.ensureStarted();
      expect(runner.isRunning, isTrue);

      await config.cacheFlags(
          const EventPipelineFlags(pipelineEnabled: false));
      expect(await runner.ensureStarted(), isFalse);
      expect(runner.isRunning, isFalse);
    });

    test('unavailable storage does not start or throw', () async {
      await config.cacheFlags(
          const EventPipelineFlags(pipelineEnabled: true));
      final noStorage = EventPipelineRunner(
        config: config,
        openDb: () async => null,
      );
      expect(await noStorage.ensureStarted(), isFalse);
    });
  });

  group('queueItems', () {
    Future<void> startWith(EventPipelineFlags flags) async {
      await config.cacheFlags(flags);
      await runner.ensureStarted();
    }

    test('freezes the resolved chain onto each item', () async {
      await startWith(const EventPipelineFlags(
        pipelineEnabled: true,
        aiEnabled: false,
        frameEnabled: true,
        frameId: 'f1',
        autoPrint: true,
      ));
      final mediaId = await seedItem();
      expect(await runner.queueItems([mediaId]), 1);

      final item = await runner.ledger!.findById(mediaId);
      expect(item!.steps, ['frame', 'print']);
      expect(item.isSelected, isTrue);
    });

    test('enqueues only the first step', () async {
      await startWith(const EventPipelineFlags(
        pipelineEnabled: true,
        frameEnabled: true,
        frameId: 'f1',
        autoPrint: true,
      ));
      final mediaId = await seedItem();
      await runner.queueItems([mediaId]);

      expect(await runner.queue!.findFor(kind: 'frame', mediaId: mediaId),
          isNotNull);
      expect(await runner.queue!.findFor(kind: 'print', mediaId: mediaId),
          isNull, reason: 'later steps are enqueued as each one completes');
    });

    test('carries the copy count onto the job', () async {
      await startWith(const EventPipelineFlags(
        pipelineEnabled: true,
        autoPrint: true,
        defaultCopies: 3,
      ));
      final mediaId = await seedItem();
      await runner.queueItems([mediaId]);
      final job = await runner.queue!.findFor(kind: 'print', mediaId: mediaId);
      expect(job!.payload['copies'], 3);
    });

    test('a settings change after queueing does not alter frozen work',
        () async {
      await startWith(const EventPipelineFlags(
        pipelineEnabled: true,
        autoPrint: true,
      ));
      final mediaId = await seedItem();
      await runner.queueItems([mediaId]);

      // The event is re-synced mid-event with framing switched on.
      await config.cacheFlags(const EventPipelineFlags(
        pipelineEnabled: true,
        autoPrint: true,
        frameEnabled: true,
        frameId: 'f9',
      ));
      await runner.refreshSettings();

      final item = await runner.ledger!.findById(mediaId);
      expect(item!.steps, ['print'],
          reason: 'in-flight items keep the plan they were queued with');
    });

    test('a later batch picks up the new settings', () async {
      await startWith(const EventPipelineFlags(
        pipelineEnabled: true,
        autoPrint: true,
      ));
      final first = await seedItem();
      await runner.queueItems([first]);

      await config.cacheFlags(const EventPipelineFlags(
        pipelineEnabled: true,
        autoPrint: true,
        frameEnabled: true,
        frameId: 'f9',
      ));
      await runner.refreshSettings();

      final second = await seedItem();
      await runner.queueItems([second]);
      final item = await runner.ledger!.findById(second);
      expect(item!.steps, ['frame', 'print']);
    });

    test('an empty chain marks the item done without queueing work', () async {
      await startWith(const EventPipelineFlags(
        pipelineEnabled: true,
        aiEnabled: false,
        frameEnabled: false,
        autoPrint: false,
      ));
      final mediaId = await seedItem();
      expect(await runner.queueItems([mediaId]), 1);

      final item = await runner.ledger!.findById(mediaId);
      expect(item!.stage, MediaStage.done);
      expect((await runner.queue!.counts('print')).total, 0);
    });

    test('an offline event queues nothing to the mirror', () async {
      await startWith(const EventPipelineFlags(
        pipelineEnabled: true,
        offlineMode: true,
        autoPrint: true,
      ));
      final mediaId = await seedItem();
      await runner.queueItems([mediaId]);

      final counts = await runner.mirror!.counts();
      expect(counts.values.fold<int>(0, (a, b) => a + b), 0);
    });

    test('an online event queues the mirror chain alongside the work',
        () async {
      await startWith(const EventPipelineFlags(
        pipelineEnabled: true,
        autoPrint: true,
        mirrorEnabled: true,
      ));
      final mediaId = await seedItem();
      await runner.queueItems([mediaId]);

      final counts = await runner.mirror!.counts();
      expect(counts.values.fold<int>(0, (a, b) => a + b), 3,
          reason: 'session, asset and row');
    });

    test('an unknown id is skipped rather than counted', () async {
      await config.cacheFlags(
          const EventPipelineFlags(pipelineEnabled: true));
      await runner.ensureStarted();
      expect(await runner.queueItems(['nope']), 0);
    });
  });
}
