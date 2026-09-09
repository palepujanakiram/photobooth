import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_info_model.dart';
import 'package:photobooth/models/event_pipeline/event_pipeline_flags.dart';
import 'package:photobooth/models/event_pipeline/media_item.dart';
import 'package:photobooth/models/event_pipeline/media_rendition.dart';
import 'package:photobooth/screens/event_pipeline/event_item_detail_viewmodel.dart';
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
  late EventPipelineLedger ledger;
  late EventPipelineQueue queue;
  late EventMediaStore media;
  late EventPipelineRunner runner;
  var ids = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    EventPipelineConfig.resetCacheForTests();
    EventPipelineRunner.resetInstanceForTests();
    EventManager.resetCacheForTests();
    root = await Directory.systemTemp.createTemp('fz_evp_detail_');
    mediaDir = Directory('${root.path}/media')..createSync(recursive: true);
    ids = 0;
    db = (await EventPipelineDb.open(root))!;
    ledger = EventPipelineLedger(db: db, newId: () => 'm${ids++}');
    queue = EventPipelineQueue(db: db);
    media = EventMediaStore(resolveDirectory: () async => mediaDir);
    await EventManager().cacheVerifyResult(
      const EventInfoModel(id: 'EVT1', code: 'GALA-01'),
    );

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

  Future<String> seed({
    String stage = MediaStage.done,
    List<String> steps = const ['frame', 'print'],
    List<String> renditions = const [
      RenditionKind.source,
      RenditionKind.framed,
    ],
    String? error,
    int? capturedAtMs,
  }) async {
    final r = await ledger.insertIfNew(
      source: MediaSource.sdCard,
      sourceRef: 'VOL-1:DCIM/100CANON/IMG_8344.JPG:6900000:1700000000000',
      contentKey: 'ck$ids',
      eventId: 'EVT1',
      originalFilename: 'IMG_8344.JPG',
      capturedAtMs: capturedAtMs,
    );
    for (final kind in renditions) {
      final path = 'EVT1/${r.item.id}-$kind.jpg';
      await media.putBytes(path, [1, 2, 3]);
      await ledger.putRendition(MediaRendition(
        mediaId: r.item.id,
        kind: kind,
        path: path,
        width: kind == RenditionKind.framed ? 1240 : 2880,
        height: kind == RenditionKind.framed ? 1920 : 1920,
        createdAtMs: 1,
      ));
    }
    if (steps.isNotEmpty) await ledger.markSelected(r.item.id, steps);
    if (stage != MediaStage.ingested) {
      await ledger.setStage(r.item.id, stage, error: error);
    }
    return r.item.id;
  }

  EventItemDetailViewModel build(String id) => EventItemDetailViewModel(
        mediaId: id,
        runner: runner,
        mediaStore: media,
      );

  group('renditions', () {
    test('shows all three side by side, present or not', () async {
      final id = await seed();
      final vm = build(id);
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.renditions.map((r) => r.label), ['Source', 'AI', 'Framed']);
      expect(vm.renditions[0].exists, isTrue);
      expect(vm.renditions[1].exists, isFalse,
          reason: 'a stage that never ran must look different from one that '
              'ran and failed');
      expect(vm.renditions[2].exists, isTrue);
    });

    test('each carries its dimensions', () async {
      final id = await seed();
      final vm = build(id);
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.renditions[0].dimensions, '2880×1920');
      expect(vm.renditions[2].dimensions, '1240×1920');
      expect(vm.renditions[1].dimensions, isNull);
    });

    test('the grid thumbnail is not one of the three', () async {
      final id = await seed(renditions: const [
        RenditionKind.source,
        RenditionKind.thumb,
      ]);
      final vm = build(id);
      await vm.start();
      addTearDown(vm.dispose);

      expect(
        vm.renditions.map((r) => r.kind),
        isNot(contains(RenditionKind.thumb)),
      );
    });
  });

  group('facts', () {
    test('names the stage and the step it stalled on', () async {
      final id = await seed(
        stage: MediaStage.failed,
        steps: const ['ai', 'frame', 'print'],
      );
      final vm = build(id);
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.stageLabel, 'Failed at AI');
      expect(vm.chainLabel, 'AI → Frame → Print');
    });

    test('shows the real error text, not a category', () async {
      final id = await seed(
        stage: MediaStage.failed,
        error: 'Ribbon end — replace ribbon',
      );
      final vm = build(id);
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.failureReason, 'Ribbon end — replace ribbon');
    });

    test("falls back to the job's error when the item carries none", () async {
      final id = await seed(stage: MediaStage.printing, steps: const ['print']);
      await queue.enqueue(kind: 'print', mediaId: id, eventId: 'EVT1');
      final job = await queue.claimReady('print');
      await queue.markFailed(job.single.id,
          error: 'Printer cover open', retryable: false);

      final vm = build(id);
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.failureReason, 'Printer cover open');
    });

    test('names the card and the folder it came off', () async {
      final id = await seed();
      final vm = build(id);
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.sourceLabel, 'VOL-1 · DCIM/100CANON/IMG_8344.JPG');
    });

    test('reports when the shutter fired, not when it was imported', () async {
      final at = DateTime(2026, 9, 9, 3, 39).millisecondsSinceEpoch;
      final id = await seed(capturedAtMs: at);
      final vm = build(id);
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.shotAt, DateTime.fromMillisecondsSinceEpoch(at));
    });

    test('an item that was never queued says so rather than showing nothing',
        () async {
      final id = await seed(stage: MediaStage.ingested, steps: const []);
      final vm = build(id);
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.chainLabel, 'Not queued yet');
      expect(vm.stageLabel, 'Imported');
    });
  });

  group('actions', () {
    test('retry is offered only on a failure, and requeues its step', () async {
      final id = await seed(stage: MediaStage.failed, steps: const ['print']);
      await queue.enqueue(kind: 'print', mediaId: id, eventId: 'EVT1');
      final job = await queue.claimReady('print');
      await queue.markFailed(job.single.id, error: 'nope', retryable: false);

      final vm = build(id);
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.canRetry, isTrue);
      await vm.retry();

      expect((await ledger.findById(id))!.stage, MediaStage.printing);
      expect(await queue.claimReady('print'), hasLength(1));
    });

    test('skip AI is offered only while AI is still in the chain', () async {
      final withAi = await seed(
        stage: MediaStage.ai,
        steps: const ['ai', 'print'],
      );
      final vmA = build(withAi);
      await vmA.start();
      addTearDown(vmA.dispose);
      expect(vmA.canSkipAi, isTrue);

      final withoutAi = await seed(steps: const ['print']);
      final vmB = build(withoutAi);
      await vmB.start();
      addTearDown(vmB.dispose);
      expect(vmB.canSkipAi, isFalse);
    });

    test('skip AI drops the step and moves the item on', () async {
      final id = await seed(stage: MediaStage.ai, steps: const ['ai', 'print']);
      await queue.enqueue(kind: 'ai', mediaId: id, eventId: 'EVT1');

      final vm = build(id);
      await vm.start();
      addTearDown(vm.dispose);
      await vm.skipAi();

      final item = await ledger.findById(id);
      expect(item!.steps, ['print']);
      expect(item.aiSkipped, isTrue);
    });

    test('reprint queues another print without re-running a stage', () async {
      final id = await seed();
      final vm = build(id);
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.canReprint, isTrue);
      await vm.reprint();

      final job = await queue.findFor(kind: 'print', mediaId: id);
      expect(job, isNotNull);
      // The operator wants another copy of what they can see, not a fresh
      // generation that might come out different.
      expect(await queue.findFor(kind: 'frame', mediaId: id), isNull);
      expect(await queue.findFor(kind: 'ai', mediaId: id), isNull);
    });

    test('reprint is not offered when nothing was ever produced', () async {
      final id = await seed(renditions: const []);
      final vm = build(id);
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.canReprint, isFalse);
    });

    test('remove deletes the row, its jobs and its files', () async {
      final id = await seed();
      await queue.enqueue(kind: 'print', mediaId: id, eventId: 'EVT1');
      final vm = build(id);
      await vm.start();
      addTearDown(vm.dispose);

      await vm.remove();

      expect(vm.isRemoved, isTrue);
      expect(await ledger.findById(id), isNull);
      expect(await queue.findFor(kind: 'print', mediaId: id), isNull);
      expect(await media.getFile('EVT1/$id-source.jpg'), isNull);
    });
  });

  test('an item that has gone reports itself removed rather than blank',
      () async {
    final vm = build('nope');
    await vm.start();
    addTearDown(vm.dispose);

    expect(vm.isRemoved, isTrue);
    expect(vm.item, isNull);
  });

  test('every stage reads as something an operator recognises', () async {
    for (final entry in const <String, String>{
      MediaStage.ingested: 'Imported',
      MediaStage.queued: 'Queued',
      MediaStage.ai: 'Waiting on AI',
      MediaStage.framing: 'Framing',
      MediaStage.printing: 'Printing',
      MediaStage.done: 'Done',
      MediaStage.paused: 'Paused',
    }.entries) {
      final id = await seed(
        stage: entry.key,
        steps: entry.key == MediaStage.ingested ? const [] : const ['print'],
      );
      final vm = build(id);
      await vm.start();
      addTearDown(vm.dispose);
      expect(vm.stageLabel, entry.value, reason: entry.key);
    }
  });

  test('an unrecognised stage falls back to its raw value', () async {
    final id = await seed(stage: 'TELEPORTING', steps: const ['print']);
    final vm = build(id);
    await vm.start();
    addTearDown(vm.dispose);
    expect(vm.stageLabel, 'TELEPORTING');
  });

  test('a failure with no current step still names itself', () async {
    final id = await seed(stage: MediaStage.failed, steps: const []);
    final vm = build(id);
    await vm.start();
    addTearDown(vm.dispose);
    expect(vm.stageLabel, 'Failed');
  });

  test('the title falls back to the id when the filename is unknown',
      () async {
    final r = await ledger.insertIfNew(
      source: MediaSource.ptp,
      sourceRef: 'camera:IMG.JPG:1:2',
      contentKey: 'ck-noname',
      eventId: 'EVT1',
      originalFilename: null,
    );
    final vm = build(r.item.id);
    await vm.start();
    addTearDown(vm.dispose);
    expect(vm.title, r.item.id);
  });

  test('a source ref with no folder part is shown as it is', () async {
    final r = await ledger.insertIfNew(
      source: MediaSource.ptp,
      sourceRef: 'bare',
      contentKey: 'ck-bare',
      eventId: 'EVT1',
    );
    final vm = build(r.item.id);
    await vm.start();
    addTearDown(vm.dispose);
    expect(vm.sourceLabel, 'bare');
  });

  test('an unknown shot time is absent rather than epoch zero', () async {
    final id = await seed();
    final vm = build(id);
    await vm.start();
    addTearDown(vm.dispose);
    expect(vm.shotAt, isNull);
  });

  test('a screen opened with no storage reports it rather than hanging',
      () async {
    final vm = EventItemDetailViewModel(
      mediaId: 'anything',
      runner: EventPipelineRunner(
        config: EventPipelineConfig(),
        mediaStore: media,
        openDb: () async => null,
      ),
      mediaStore: media,
    );
    await vm.start();
    addTearDown(vm.dispose);

    expect(vm.errorMessage, 'Storage is unavailable.');
    expect(vm.isBusy, isFalse);
  });

  test('a read that throws is reported, not swallowed', () async {
    final id = await seed();
    final vm = build(id);
    await vm.start();
    addTearDown(vm.dispose);

    // A closed handle stands in for the disk going away mid-event.
    await db.close();
    await vm.refresh();
    expect(vm.errorMessage, 'Could not read this photo.');

    // Reopen so tearDown's close does not throw.
    db = (await EventPipelineDb.open(root))!;
  });

  group('step timings', () {
    test('reports when each step finished and what it cost', () async {
      final id = await seed(stage: MediaStage.done, steps: const ['print']);
      final queue = EventPipelineQueue(db: db);
      await queue.enqueue(kind: 'print', mediaId: id, eventId: 'EVT1');
      final claimed = await queue.claimReady('print');
      await queue.markDone(claimed.single.id);

      final vm = build(id);
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.timings, hasLength(1));
      final t = vm.timings.single;
      expect(t.label, 'Print');
      expect(t.finishedAt, isNotNull);
      expect(t.startedAtMs, isNotNull);
      expect(t.work, isNotNull);
    });

    test('a step still waiting has no start and no duration', () async {
      final id = await seed(stage: MediaStage.printing, steps: const ['print']);
      final queue = EventPipelineQueue(db: db);
      await queue.enqueue(kind: 'print', mediaId: id, eventId: 'EVT1');

      final vm = build(id);
      await vm.start();
      addTearDown(vm.dispose);

      final t = vm.timings.single;
      expect(t.startedAtMs, isNull);
      expect(t.work, isNull);
      expect(t.wait, isNull);
      expect(t.finishedAt, isNull,
          reason: 'reporting the last transition as a finish would invent a '
              'duration for work that has not happened');
    });

    test('a running step reports no finish time', () async {
      final id = await seed(stage: MediaStage.printing, steps: const ['print']);
      final queue = EventPipelineQueue(db: db);
      await queue.enqueue(kind: 'print', mediaId: id, eventId: 'EVT1');
      await queue.claimReady('print');

      final vm = build(id);
      await vm.start();
      addTearDown(vm.dispose);

      final t = vm.timings.single;
      expect(t.startedAtMs, isNotNull);
      expect(t.finishedAt, isNull);
      expect(t.wait, isNotNull, reason: 'the queue wait is already known');
    });

    test('one row per step of the frozen chain', () async {
      final id = await seed(
        stage: MediaStage.done,
        steps: const ['ai', 'frame', 'print'],
      );
      final queue = EventPipelineQueue(db: db);
      for (final kind in const ['ai', 'frame', 'print']) {
        await queue.enqueue(kind: kind, mediaId: id, eventId: 'EVT1');
      }

      final vm = build(id);
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.timings.map((t) => t.label), ['AI', 'Frame', 'Print']);
    });

    test('an item that was never queued has no timings', () async {
      final id = await seed(stage: MediaStage.ingested, steps: const []);
      final vm = build(id);
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.timings, isEmpty);
    });

    test('a failed step still reports what it cost before failing', () async {
      final id = await seed(stage: MediaStage.failed, steps: const ['print']);
      final queue = EventPipelineQueue(db: db);
      await queue.enqueue(kind: 'print', mediaId: id, eventId: 'EVT1');
      final claimed = await queue.claimReady('print');
      await queue.markFailed(claimed.single.id,
          error: 'ribbon', retryable: false);

      final vm = build(id);
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.timings.single.finishedAt, isNotNull);
    });
  });
}
