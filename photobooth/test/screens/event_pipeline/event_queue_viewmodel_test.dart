import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_pipeline/event_pipeline_flags.dart';
import 'package:photobooth/models/event_pipeline/media_item.dart';
import 'package:photobooth/models/event_pipeline/media_rendition.dart';
import 'package:photobooth/screens/event_pipeline/event_queue_viewmodel.dart';
import 'package:photobooth/services/event_pipeline/event_media_store.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_config.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_db.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_ledger.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_runner.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory mediaDir;
  late EventPipelineDb db;
  late EventPipelineRunner runner;
  late EventMediaStore media;
  var ids = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    EventPipelineConfig.resetCacheForTests();
    EventPipelineRunner.resetInstanceForTests();
    root = await Directory.systemTemp.createTemp('fz_evp_queue_');
    mediaDir = Directory('${root.path}/media')..createSync(recursive: true);
    ids = 0;
    db = (await EventPipelineDb.open(root))!;
    media = EventMediaStore(resolveDirectory: () async => mediaDir);

    final config = EventPipelineConfig();
    await config.cacheFlags(
      const EventPipelineFlags(pipelineEnabled: true, autoPrint: true),
    );
    runner = EventPipelineRunner(
      config: config,
      mediaStore: media,
      openDb: () async => db,
    );
    await runner.ensureStarted();
  });

  tearDown(() async {
    runner.stop();
    EventPipelineRunner.resetInstanceForTests();
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// Seeds an item at [stage], with a derivative on disk when asked.
  Future<String> seed({
    required String stage,
    bool withRendition = true,
    String? filename,
  }) async {
    final ledger = EventPipelineLedger(db: db, newId: () => 'm${ids++}');
    final r = await ledger.insertIfNew(
      source: MediaSource.sdCard,
      sourceRef: 'V:$ids',
      contentKey: 'ck$ids',
      eventId: 'EVT1',
      originalFilename: filename ?? 'IMG_$ids.JPG',
    );
    if (withRendition) {
      final path = 'EVT1/${r.item.id}-source.jpg';
      await media.putBytes(path, [1, 2, 3]);
      await ledger.putRendition(MediaRendition(
        mediaId: r.item.id,
        kind: RenditionKind.source,
        path: path,
        createdAtMs: 1,
      ));
    }
    if (stage != MediaStage.ingested) {
      await ledger.setStage(r.item.id, stage);
    }
    return r.item.id;
  }

  EventQueueViewModel build() => EventQueueViewModel(
        runner: runner,
        mediaStore: media,
        refreshInterval: const Duration(hours: 1),
      );

  group('listing', () {
    test('an empty pipeline reports empty', () async {
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);
      expect(vm.isEmpty, isTrue);
      expect(vm.isFilteredEmpty, isFalse);
    });

    test('imported photos are visible with their picture', () async {
      await seed(stage: MediaStage.ingested, filename: 'IMG_8344.JPG');
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.entries, hasLength(1));
      final entry = vm.entries.single;
      expect(entry.item.originalFilename, 'IMG_8344.JPG');
      expect(entry.thumbnailFile, isNotNull,
          reason: 'the derivative on disk is what the grid shows');
      expect(entry.stageLabel, 'Imported');
    });

    test('an item with no derivative still lists, without a picture', () async {
      await seed(stage: MediaStage.ingested, withRendition: false);
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);
      expect(vm.entries.single.thumbnailFile, isNull);
    });

    test('failures sort ahead of finished work', () async {
      await seed(stage: MediaStage.done);
      await seed(stage: MediaStage.failed);
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);
      expect(vm.entries.first.isFailed, isTrue);
      expect(vm.entries.last.isDone, isTrue);
    });

    test('a skipped-AI result reads differently from a normal one', () async {
      final id = await seed(stage: MediaStage.done);
      final ledger = EventPipelineLedger(db: db);
      await ledger.markSelected(id, const ['ai', 'print']);
      await ledger.skipAi(id, newSteps: const ['print']);
      await ledger.setStage(id, MediaStage.done);

      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);
      expect(vm.entries.single.stageLabel, 'Done · AI skipped');
    });
  });

  group('filters', () {
    test('only stages holding photos get a chip', () async {
      await seed(stage: MediaStage.ingested);
      await seed(stage: MediaStage.done);
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      final labels = vm.filterOptions.map((o) => o.label).toList();
      expect(labels, ['All', 'Imported', 'Done']);
      // An AI-off event must not carry a permanently empty AI filter.
      expect(labels.contains('AI'), isFalse);
    });

    test('counts are live per stage', () async {
      await seed(stage: MediaStage.ingested);
      await seed(stage: MediaStage.ingested);
      await seed(stage: MediaStage.failed);
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      final byLabel = {for (final o in vm.filterOptions) o.label: o.count};
      expect(byLabel['All'], 3);
      expect(byLabel['Imported'], 2);
      expect(byLabel['Failed'], 1);
    });

    test('selecting a filter narrows the grid', () async {
      await seed(stage: MediaStage.ingested);
      await seed(stage: MediaStage.done);
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.visibleEntries, hasLength(2));
      vm.setFilter(MediaStage.done);
      expect(vm.visibleEntries, hasLength(1));
      expect(vm.visibleEntries.single.isDone, isTrue);
    });

    test('All restores everything', () async {
      await seed(stage: MediaStage.ingested);
      await seed(stage: MediaStage.done);
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      vm.setFilter(MediaStage.done);
      vm.setFilter(QueueFilter.all);
      expect(vm.visibleEntries, hasLength(2));
    });

    test('chips follow the order a photo actually travels', () {
      expect(QueueFilter.stageOrder, [
        MediaStage.ingested,
        MediaStage.queued,
        MediaStage.ai,
        MediaStage.framing,
        MediaStage.printing,
        MediaStage.done,
        MediaStage.failed,
      ]);
    });
  });

  group('actions', () {
    test('Skip AI is offered only for items stuck on AI', () async {
      await seed(stage: MediaStage.ingested);
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);
      expect(vm.stuckOnAi, isEmpty);

      await seed(stage: MediaStage.ai);
      await vm.refresh();
      expect(vm.stuckOnAi, hasLength(1));
    });

    test('retry is offered only when something failed', () async {
      await seed(stage: MediaStage.done);
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);
      expect(vm.hasFailed, isFalse);

      await seed(stage: MediaStage.failed);
      await vm.refresh();
      expect(vm.hasFailed, isTrue);
      expect(vm.failedCount, 1);
    });

    test('retry puts a failed item back on its current step', () async {
      final id = await seed(stage: MediaStage.ingested);
      final ledger = EventPipelineLedger(db: db);
      await ledger.markSelected(id, const ['print']);
      await ledger.setStage(id, MediaStage.failed, error: 'no printer');

      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);
      expect(vm.hasFailed, isTrue);

      await vm.retryFailed();
      final reloaded = await ledger.findById(id);
      expect(reloaded!.stage, MediaStage.printing);
    });
  });
}
