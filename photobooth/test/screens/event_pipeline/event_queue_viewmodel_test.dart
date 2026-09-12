import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_pipeline/event_pipeline_flags.dart';
import 'package:photobooth/models/event_pipeline/media_item.dart';
import 'package:photobooth/models/event_info_model.dart';
import 'package:photobooth/models/event_pipeline/media_rendition.dart';
import 'package:photobooth/screens/event_pipeline/event_queue_viewmodel.dart';
import 'package:photobooth/services/event_manager.dart';
import 'package:photobooth/services/event_pipeline/event_media_store.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_config.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_db.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_ledger.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_queue.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_runner.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory mediaDir;
  late EventPipelineDb db;
  late EventPipelineRunner runner;
  late EventMediaStore media;
  late EventPipelineLedger ledger;
  var ids = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    EventPipelineConfig.resetCacheForTests();
    EventPipelineRunner.resetInstanceForTests();
    EventManager.resetCacheForTests();
    // Every read is scoped to the bound event, so the queue needs one bound.
    await EventManager().cacheVerifyResult(
      const EventInfoModel(id: 'EVT1', code: 'GALA-01'),
    );
    root = await Directory.systemTemp.createTemp('fz_evp_queue_');
    mediaDir = Directory('${root.path}/media')..createSync(recursive: true);
    ids = 0;
    db = (await EventPipelineDb.open(root))!;
    media = EventMediaStore(resolveDirectory: () async => mediaDir);
    ledger = EventPipelineLedger(db: db);

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
    String? eventId = 'EVT1',
    String source = MediaSource.sdCard,
  }) async {
    final ledger = EventPipelineLedger(db: db, newId: () => 'm${ids++}');
    final r = await ledger.insertIfNew(
      source: source,
      sourceRef: 'V:$ids',
      contentKey: 'ck$ids',
      eventId: eventId,
      originalFilename: filename ?? 'IMG_$ids.JPG',
    );
    if (withRendition) {
      for (final kind in const [RenditionKind.source, RenditionKind.thumb]) {
        final path = '${eventId ?? 'unassigned'}/${r.item.id}-$kind.jpg';
        await media.putBytes(path, [1, 2, 3]);
        await ledger.putRendition(MediaRendition(
          mediaId: r.item.id,
          kind: kind,
          path: path,
          createdAtMs: 1,
        ));
      }
    }
    if (stage != MediaStage.ingested) {
      await ledger.setStage(r.item.id, stage);
    }
    return r.item.id;
  }

  EventQueueViewModel build({String? initialFilter, int pageSize = 60}) =>
      EventQueueViewModel(
        runner: runner,
        mediaStore: media,
        initialFilter: initialFilter,
        pageSize: pageSize,
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
      await vm.setFilter(MediaStage.done);
      expect(vm.visibleEntries, hasLength(1));
      expect(vm.visibleEntries.single.isDone, isTrue);
    });

    test('the hub opens the queue already filtered to the tapped counter',
        () async {
      await seed(stage: MediaStage.ingested);
      await seed(stage: MediaStage.failed);
      final vm = build(initialFilter: MediaStage.failed);
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.filter, MediaStage.failed);
      expect(vm.visibleEntries, hasLength(1));
    });

    test('WORKING collapses the three in-flight stages, as the hub shows them',
        () async {
      await seed(stage: MediaStage.ai);
      await seed(stage: MediaStage.framing);
      await seed(stage: MediaStage.printing);
      await seed(stage: MediaStage.done);
      final vm = build(initialFilter: QueueFilter.working);
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.visibleEntries, hasLength(3));
    });

    test('an unknown route argument opens the whole queue, not an empty grid',
        () async {
      await seed(stage: MediaStage.ingested);
      final vm = build(initialFilter: 'nonsense');
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.filter, QueueFilter.all);
      expect(vm.visibleEntries, hasLength(1));
    });

    test('normalize accepts what the hub passes and nothing else', () {
      expect(QueueFilter.normalize(null), QueueFilter.all);
      expect(QueueFilter.normalize('  '), QueueFilter.all);
      expect(QueueFilter.normalize('all'), QueueFilter.all);
      expect(QueueFilter.normalize('working'), QueueFilter.working);
      expect(QueueFilter.normalize('failed'), MediaStage.failed);
      expect(QueueFilter.normalize('teleport'), QueueFilter.all);
    });

    test('All restores everything', () async {
      await seed(stage: MediaStage.ingested);
      await seed(stage: MediaStage.done);
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      await vm.setFilter(MediaStage.done);
      await vm.setFilter(QueueFilter.all);
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

  group('event scoping', () {
    test("another event's photos never appear", () async {
      await seed(stage: MediaStage.done);
      await seed(stage: MediaStage.failed, eventId: 'OTHER-EVENT');
      await seed(stage: MediaStage.done, eventId: 'OTHER-EVENT');

      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      // The ledger is durable across events, so without scoping an operator
      // opening the queue at a wedding would see last weekend's party — wrong
      // counts, and a real chance of reprinting the wrong couple's photos.
      expect(vm.visibleEntries, hasLength(1));
      expect(vm.totalInFilter, 1);
      expect(vm.stats.total, 1);
      expect(vm.stats.failed, 0,
          reason: "the other event's failure must not raise this one's alarm");
    });

    test('unassigned photos are not folded into an event', () async {
      await seed(stage: MediaStage.done);
      await seed(stage: MediaStage.done, eventId: null);

      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.visibleEntries, hasLength(1));
    });

    test('the counters the chips show are scoped too', () async {
      await seed(stage: MediaStage.failed);
      await seed(stage: MediaStage.failed, eventId: 'OTHER-EVENT');

      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      final byLabel = {for (final o in vm.filterOptions) o.label: o.count};
      expect(byLabel['Failed'], 1);
      expect(byLabel['All'], 1);
    });
  });

  group('pagination', () {
    test('loads one page, then more on demand', () async {
      for (var i = 0; i < 7; i++) {
        await seed(stage: MediaStage.done);
      }
      final vm = build(pageSize: 3);
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.visibleEntries, hasLength(3));
      expect(vm.totalInFilter, 7);
      expect(vm.hasMore, isTrue);

      await vm.loadMore();
      expect(vm.visibleEntries, hasLength(6));
      expect(vm.hasMore, isTrue);

      await vm.loadMore();
      expect(vm.visibleEntries, hasLength(7));
      expect(vm.hasMore, isFalse);
    });

    test('a poll keeps the pages already on screen', () async {
      for (var i = 0; i < 6; i++) {
        await seed(stage: MediaStage.done);
      }
      final vm = build(pageSize: 2);
      await vm.start();
      addTearDown(vm.dispose);
      await vm.loadMore();
      expect(vm.visibleEntries, hasLength(4));

      // The refresh timer must not scroll the operator back to the top.
      await vm.refresh();
      expect(vm.visibleEntries, hasLength(4));
    });

    test('load more past the end is a no-op', () async {
      await seed(stage: MediaStage.done);
      final vm = build(pageSize: 10);
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.hasMore, isFalse);
      await vm.loadMore();
      expect(vm.visibleEntries, hasLength(1));
    });

    test('pages are scoped to the filter, not filtered after loading',
        () async {
      for (var i = 0; i < 4; i++) {
        await seed(stage: MediaStage.done);
      }
      await seed(stage: MediaStage.failed);

      final vm = build(pageSize: 2, initialFilter: MediaStage.failed);
      await vm.start();
      addTearDown(vm.dispose);

      // A filter applied in memory over a page would show nothing here.
      expect(vm.visibleEntries, hasLength(1));
      expect(vm.hasMore, isFalse);
    });
  });

  group('selection', () {
    test('nothing acts until something is ticked', () async {
      await seed(stage: MediaStage.failed);
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      vm.enterSelection();
      expect(vm.selectionMode, isTrue);
      expect(vm.hasSelection, isFalse);
      expect(vm.canRetrySelected, isFalse);
      expect(vm.canReprintSelected, isFalse);
      expect(vm.canRemoveSelected, isFalse);
    });

    test('actions appear only when valid for the selection', () async {
      await seed(stage: MediaStage.failed);
      await seed(stage: MediaStage.done);
      await seed(stage: MediaStage.ai);
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      final failed = vm.visibleEntries.firstWhere((e) => e.isFailed);
      vm.enterSelection();
      vm.toggleSelected(failed);
      expect(vm.canRetrySelected, isTrue);
      expect(vm.canReprintSelected, isFalse,
          reason: 'nothing finished is ticked');
      expect(vm.canSkipAiSelected, isFalse);

      vm.selectNone();
      final done = vm.visibleEntries.firstWhere((e) => e.isDone);
      vm.toggleSelected(done);
      expect(vm.canReprintSelected, isTrue);
      expect(vm.canRetrySelected, isFalse);
    });

    test('an action applies only to what is ticked', () async {
      final failedA = await seed(stage: MediaStage.failed);
      await seed(stage: MediaStage.failed);
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      vm.enterSelection();
      vm.toggleSelected(
        vm.visibleEntries.firstWhere((e) => e.item.id == failedA),
      );
      final n = await vm.removeSelected();

      expect(n, 1, reason: 'a bare act-on-everything is what this replaces');
      expect(vm.visibleEntries, hasLength(1));
      expect(vm.visibleEntries.single.item.id, isNot(failedA));
    });

    test('retry requeues only the ticked failures', () async {
      final a = await seed(stage: MediaStage.failed);
      final b = await seed(stage: MediaStage.failed);
      final queue = EventPipelineQueue(db: db);
      for (final id in [a, b]) {
        await ledger.markSelected(id, const ['print']);
        await ledger.setStage(id, MediaStage.failed);
        await queue.enqueue(kind: 'print', mediaId: id, eventId: 'EVT1');
        final job = await queue.findFor(kind: 'print', mediaId: id);
        await queue.claimReady('print');
        await queue.markFailed(job!.id, error: 'nope', retryable: false);
      }

      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      vm.enterSelection();
      vm.toggleSelected(vm.visibleEntries.firstWhere((e) => e.item.id == a));
      final n = await vm.retrySelected();

      expect(n, 1);
      expect((await ledger.findById(a))!.stage, MediaStage.printing);
      expect((await ledger.findById(b))!.stage, MediaStage.failed,
          reason: 'a bare retry-all is what selection replaces');
    });

    test('skip AI drops the step on the ticked items only', () async {
      final a = await seed(stage: MediaStage.ingested);
      final b = await seed(stage: MediaStage.ingested);
      final queue = EventPipelineQueue(db: db);
      for (final id in [a, b]) {
        await ledger.markSelected(id, const ['ai', 'print']);
        await ledger.setStage(id, MediaStage.ai);
        await queue.enqueue(kind: 'ai', mediaId: id, eventId: 'EVT1');
      }

      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      vm.enterSelection();
      vm.toggleSelected(vm.visibleEntries.firstWhere((e) => e.item.id == a));
      final n = await vm.skipAiSelected();

      expect(n, 1);
      expect((await ledger.findById(a))!.steps, ['print']);
      expect((await ledger.findById(b))!.steps, ['ai', 'print']);
    });

    test('retry ignores ticked items that are not failures', () async {
      await seed(stage: MediaStage.done);
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      vm.selectAllLoaded();
      expect(await vm.retrySelected(), 0);
    });

    test('All ticks the loaded page and None clears it', () async {
      for (var i = 0; i < 3; i++) {
        await seed(stage: MediaStage.done);
      }
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      vm.selectAllLoaded();
      expect(vm.selectionMode, isTrue);
      expect(vm.selectedCount, 3);
      vm.selectNone();
      expect(vm.selectedCount, 0);
    });

    test('changing the filter clears the ticks', () async {
      await seed(stage: MediaStage.done);
      await seed(stage: MediaStage.failed);
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      vm.selectAllLoaded();
      expect(vm.selectedCount, 2);
      await vm.setFilter(MediaStage.failed);

      // Ticks carried across a filter change would let an action reach items
      // the operator can no longer see.
      expect(vm.selectedCount, 0);
    });

    test('removing an item takes its files with it', () async {
      final id = await seed(stage: MediaStage.done);
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      vm.selectAllLoaded();
      await vm.removeSelected();

      expect(vm.visibleEntries, isEmpty);
      final ledger = EventPipelineLedger(db: db);
      expect(await ledger.findById(id), isNull);
      expect(await media.getFile('EVT1/$id-thumb.jpg'), isNull);
    });

    test('an action leaves selection mode when it is done', () async {
      await seed(stage: MediaStage.done);
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      vm.selectAllLoaded();
      await vm.reprintSelected();
      expect(vm.selectionMode, isFalse);
      expect(vm.hasSelection, isFalse);
    });

    test('exiting selection clears the ticks', () async {
      await seed(stage: MediaStage.done);
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      vm.selectAllLoaded();
      vm.exitSelection();
      expect(vm.selectionMode, isFalse);
      expect(vm.selectedCount, 0);
    });
  });

  group('pause and resume', () {
    test('pausing holds every stage, not just one', () async {
      final id = await seed(stage: MediaStage.queued);
      final queue = EventPipelineQueue(db: db);
      await queue.enqueue(kind: 'frame', mediaId: id);
      await queue.enqueue(kind: 'print', mediaId: id);

      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      await vm.setPaused(true);
      expect(vm.isPaused, isTrue);
      expect(await queue.claimReady('frame'), isEmpty);
      expect(await queue.claimReady('print'), isEmpty);
    });

    test('pause survives a restart — it is queue state, not screen state',
        () async {
      final first = build();
      await first.start();
      await first.setPaused(true);
      first.dispose();

      final second = build();
      await second.start();
      addTearDown(second.dispose);

      expect(second.isPaused, isTrue);
    });

    test('pausing an empty queue still holds the work that arrives next',
        () async {
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);
      await vm.setPaused(true);

      final queue = EventPipelineQueue(db: db);
      await queue.enqueue(kind: 'print', mediaId: 'later');
      expect(await queue.claimReady('print'), isEmpty,
          reason: 'a pause derived from job rows would have missed this');
    });

    test('resuming releases the work', () async {
      final queue = EventPipelineQueue(db: db);
      await queue.enqueue(kind: 'print', mediaId: 'm1');

      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      await vm.setPaused(true);
      expect(await queue.claimReady('print'), isEmpty);

      await vm.setPaused(false);
      expect(vm.isPaused, isFalse);
      expect(await queue.claimReady('print'), hasLength(1));
    });

    test('processing is the live indicator, and pausing stops it', () async {
      await seed(stage: MediaStage.framing);
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.isProcessing, isTrue);
      await vm.setPaused(true);
      expect(vm.isProcessing, isFalse);
    });
  });

  group('print queue position', () {
    test('only the job on the printer says Printing', () async {
      final queue = EventPipelineQueue(db: db);
      final ids = <String>[];
      for (var i = 0; i < 3; i++) {
        final id = await seed(stage: MediaStage.printing);
        ids.add(id);
        await queue.enqueue(kind: 'print', mediaId: id, eventId: 'EVT1');
      }
      // One is claimed — that is the one actually on the printer.
      await queue.claimReady('print', limit: 1);

      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      final printing =
          vm.visibleEntries.where((e) => e.stageLabel == 'Printing').toList();
      expect(printing, hasLength(1),
          reason: 'three photos all reading Printing is simply untrue');
      expect(printing.single.isOnPrinter, isTrue);
    });

    test('the rest are numbered in the order they will run', () async {
      final queue = EventPipelineQueue(db: db);
      final ids = <String>[];
      for (var i = 0; i < 3; i++) {
        final id = await seed(stage: MediaStage.printing);
        ids.add(id);
        await queue.enqueue(kind: 'print', mediaId: id, eventId: 'EVT1');
      }

      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      final byId = {for (final e in vm.visibleEntries) e.item.id: e};
      expect(byId[ids[0]]!.printPosition, 1);
      expect(byId[ids[1]]!.printPosition, 2);
      expect(byId[ids[2]]!.printPosition, 3);
      expect(byId[ids[1]]!.stageLabel, 'In print queue · 2');
    });

    test('the one on the printer has left the queue, so has no number',
        () async {
      final queue = EventPipelineQueue(db: db);
      final first = await seed(stage: MediaStage.printing);
      final second = await seed(stage: MediaStage.printing);
      await queue.enqueue(kind: 'print', mediaId: first, eventId: 'EVT1');
      await queue.enqueue(kind: 'print', mediaId: second, eventId: 'EVT1');
      await queue.claimReady('print', limit: 1);

      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      final byId = {for (final e in vm.visibleEntries) e.item.id: e};
      expect(byId[first]!.printPosition, isNull);
      expect(byId[second]!.printPosition, 1,
          reason: 'the next one up is first in the queue, not second');
    });

    test('a photo not waiting to print carries no position', () async {
      await seed(stage: MediaStage.done);
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.visibleEntries.single.printPosition, isNull);
      expect(vm.visibleEntries.single.isOnPrinter, isFalse);
    });

    test('a print stage with no job row still reads as queued, not printing',
        () async {
      await seed(stage: MediaStage.printing);
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.visibleEntries.single.stageLabel, 'In print queue');
    });
  });

  group('source', () {
    test('one source alone offers nothing to choose between', () async {
      await seed(stage: MediaStage.done);
      await seed(stage: MediaStage.done);
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      // A single dead chip is clutter on a screen that must stay readable.
      expect(vm.sourceOptions, isEmpty);
    });

    test('two sources get chips with their counts', () async {
      await seed(stage: MediaStage.done);
      await seed(stage: MediaStage.done, source: MediaSource.ptp);
      await seed(stage: MediaStage.done, source: MediaSource.ptp);
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      final byLabel = {for (final o in vm.sourceOptions) o.label: o.count};
      expect(byLabel['All sources'], 3);
      expect(byLabel['Camera'], 2);
      expect(byLabel['Card'], 1);
    });

    test('tethered shots come first, being what is actively producing',
        () async {
      await seed(stage: MediaStage.done);
      await seed(stage: MediaStage.done, source: MediaSource.ptp);
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.sourceOptions[1].label, 'Camera');
      expect(vm.sourceOptions[2].label, 'Card');
    });

    test('filtering to a source narrows the grid', () async {
      await seed(stage: MediaStage.done);
      final camera = await seed(
        stage: MediaStage.done,
        source: MediaSource.ptp,
      );
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);
      expect(vm.visibleEntries, hasLength(2));

      await vm.setSourceFilter(MediaSource.ptp);
      expect(vm.visibleEntries, hasLength(1));
      expect(vm.visibleEntries.single.item.id, camera);
      expect(vm.totalInFilter, 1);
    });

    test('All sources restores everything', () async {
      await seed(stage: MediaStage.done);
      await seed(stage: MediaStage.done, source: MediaSource.ptp);
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      await vm.setSourceFilter(MediaSource.ptp);
      await vm.setSourceFilter(QueueFilter.allSources);
      expect(vm.sourceFilter, isNull);
      expect(vm.visibleEntries, hasLength(2));
    });

    test('source and stage filters compose', () async {
      await seed(stage: MediaStage.failed);
      await seed(stage: MediaStage.failed, source: MediaSource.ptp);
      await seed(stage: MediaStage.done, source: MediaSource.ptp);
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      await vm.setSourceFilter(MediaSource.ptp);
      await vm.setFilter(MediaStage.failed);
      expect(vm.visibleEntries, hasLength(1));
    });

    test('changing source clears the ticks', () async {
      await seed(stage: MediaStage.done);
      await seed(stage: MediaStage.done, source: MediaSource.ptp);
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      vm.selectAllLoaded();
      expect(vm.selectedCount, 2);
      await vm.setSourceFilter(MediaSource.ptp);
      expect(vm.selectedCount, 0);
    });

    test('source counts are scoped to the event like everything else',
        () async {
      await seed(stage: MediaStage.done, source: MediaSource.ptp);
      await seed(
        stage: MediaStage.done,
        source: MediaSource.ptp,
        eventId: 'OTHER-EVENT',
      );
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      // Only one source present for this event, so no chips at all.
      expect(vm.sourceOptions, isEmpty);
      expect(vm.visibleEntries, hasLength(1));
    });
  });

  group('MediaSource labels', () {
    test('every source an operator can see has a name', () {
      for (final source in MediaSource.filterOrder) {
        expect(MediaSource.labelFor(source), isNotEmpty);
      }
      expect(MediaSource.labelFor(MediaSource.sdCard), 'Card');
      expect(MediaSource.labelFor(MediaSource.ptp), 'Camera');
    });

    test('an unknown source falls back to its raw value', () {
      expect(MediaSource.labelFor('telepathy'), 'telepathy');
    });
  });

  group('QueueFilter.apply', () {
    const queued = MediaItem(
      id: 'a',
      source: MediaSource.ptp,
      sourceRef: 'r1',
      contentKey: 'k1',
      stage: MediaStage.queued,
      createdAtMs: 1,
      updatedAtMs: 1,
    );
    const ai = MediaItem(
      id: 'b',
      source: MediaSource.sdCard,
      sourceRef: 'r2',
      contentKey: 'k2',
      stage: MediaStage.ai,
      createdAtMs: 1,
      updatedAtMs: 1,
    );

    test('working keeps in-flight stages', () {
      expect(
        QueueFilter.apply(const [queued, ai], filter: QueueFilter.working)
            .map((i) => i.id),
        ['b'],
      );
    });

    test('all keeps every item', () {
      expect(
        QueueFilter.apply(const [queued, ai], filter: QueueFilter.all),
        hasLength(2),
      );
    });

    test('a missing source match is empty', () {
      expect(
        QueueFilter.apply(
          const [queued],
          filter: QueueFilter.all,
          source: MediaSource.sdCard,
        ),
        isEmpty,
      );
    });

    test('a stage filter and a source filter compose', () {
      expect(
        QueueFilter.apply(
          const [queued, ai],
          filter: MediaStage.queued,
          source: MediaSource.ptp,
        ).single.id,
        'a',
      );
    });

    test('source counts group origins', () {
      expect(
        QueueFilter.sourceCounts(const [queued, ai]),
        {MediaSource.ptp: 1, MediaSource.sdCard: 1},
      );
    });
  });
}
