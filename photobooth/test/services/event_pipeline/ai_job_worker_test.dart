import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_pipeline/event_pipeline_settings.dart';
import 'package:photobooth/models/event_pipeline/media_item.dart';
import 'package:photobooth/models/event_pipeline/media_rendition.dart';
import 'package:photobooth/models/event_pipeline/pipeline_job.dart';
import 'package:photobooth/models/parallel_generation_result.dart';
import 'package:photobooth/services/api_service.dart';
import 'package:photobooth/services/event_pipeline/ai_job_worker.dart';
import 'package:photobooth/services/event_pipeline/event_media_store.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_db.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_ledger.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_queue.dart';
import 'package:photobooth/utils/exceptions.dart';

/// Manual fake by subclass-and-override, per the repo convention.
class FakeApi extends ApiService {
  FakeApi();

  ParallelGenerationResult? result;
  Object? throwThis;
  int calls = 0;
  String? lastSessionId;
  String? lastPhotoId;
  String? lastThemeId;
  int? lastCount;

  @override
  Future<ParallelGenerationResult> generateImages({
    required String sessionId,
    required int count,
    required int attempt,
    required String originalPhotoId,
    required String themeId,
    void Function(String message)? onProgress,
    void Function(String eventType, Map<String, dynamic> json)? onSseEvent,
  }) async {
    calls++;
    lastSessionId = sessionId;
    lastPhotoId = originalPhotoId;
    lastThemeId = themeId;
    lastCount = count;
    final err = throwThis;
    if (err != null) throw err;
    return result ??
        ParallelGenerationResult(imageUrlsBySlot: const ['https://x/ai.jpg']);
  }
}

EventPipelineSettings settingsWith({
  String? themeId = 'theme-1',
  bool offline = false,
}) {
  return EventPipelineSettings(
    pipelineEnabled: true,
    offlineMode: offline,
    aiEnabled: true,
    themeId: themeId,
    frameEnabled: false,
    autoPrint: true,
    defaultCopies: 1,
    printSize: 's4x6',
    qualityFactor: 1.0,
    mirrorEnabled: true,
    scanFolders: const ['DCIM'],
  );
}

void main() {
  late Directory root;
  late Directory mediaDir;
  late EventPipelineDb db;
  late EventPipelineLedger ledger;
  late EventPipelineQueue queue;
  late EventMediaStore mediaStore;
  late FakeApi api;
  var ids = 0;
  var clock = 1000;
  var fetched = <String>[];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fz_evp_ai_');
    mediaDir = Directory('${root.path}/media')..createSync(recursive: true);
    ids = 0;
    clock = 1000;
    fetched = <String>[];
    db = (await EventPipelineDb.open(root))!;
    ledger = EventPipelineLedger(db: db, newId: () => 'm${ids++}');
    queue = EventPipelineQueue(
      db: db,
      newId: () => 'j${ids++}',
      nowMs: () => clock,
    );
    mediaStore = EventMediaStore(resolveDirectory: () async => mediaDir);
    api = FakeApi();
  });

  tearDown(() async {
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<String> seedItem({
    String? sessionId = 'sess-1',
    String? photoId = 'photo-1',
  }) async {
    final result = await ledger.insertIfNew(
      source: MediaSource.sdCard,
      sourceRef: 'VOL:DCIM/${ids}A.JPG:1:2',
      contentKey: 'ck-$ids',
      eventId: 'EVT1',
    );
    final path = 'EVT1/${result.item.id}-source.jpg';
    await mediaStore.putBytes(path, [1, 2, 3]);
    await ledger.putRendition(MediaRendition(
      mediaId: result.item.id,
      kind: RenditionKind.source,
      path: path,
      createdAtMs: 1,
    ));
    if (sessionId != null || photoId != null) {
      await ledger.setRemoteIds(
        result.item.id,
        sessionId: sessionId,
        photoId: photoId,
      );
    }
    return result.item.id;
  }

  AiJobWorker buildWorker({EventPipelineSettings? settings}) {
    return AiJobWorker(
      queue: queue,
      ledger: ledger,
      mediaStore: mediaStore,
      api: api,
      settings: () => settings ?? settingsWith(),
      fetchImage: (url) async {
        fetched.add(url);
        return List<int>.filled(2048, 8);
      },
      nowMs: () => 5,
    );
  }

  group('generation', () {
    test('generates, stores the result and advances the chain', () async {
      final mediaId = await seedItem();
      await ledger.markSelected(mediaId, const ['ai', 'print']);
      await queue.enqueue(kind: 'ai', mediaId: mediaId, eventId: 'EVT1');

      expect(await buildWorker().drain(), 1);

      expect(api.calls, 1);
      expect(api.lastSessionId, 'sess-1');
      expect(api.lastPhotoId, 'photo-1');
      expect(api.lastThemeId, 'theme-1');
      expect(fetched, ['https://x/ai.jpg']);

      final best = await ledger.bestRenditionForPrint(mediaId);
      expect(best!.kind, RenditionKind.ai);

      final item = await ledger.findById(mediaId);
      expect(item!.currentStep, 'print');
      expect(await queue.findFor(kind: 'print', mediaId: mediaId), isNotNull);
    });

    test('asks for exactly one image', () async {
      // The guest flow generates several so a person can choose. Here there is
      // nobody choosing, and every extra slot is money.
      final mediaId = await seedItem();
      await queue.enqueue(kind: 'ai', mediaId: mediaId);
      await buildWorker().drain();
      expect(api.lastCount, 1);
    });

    test('prefers the highest-quality slot', () async {
      api.result = ParallelGenerationResult(
        imageUrlsBySlot: const ['https://x/a.jpg', 'https://x/b.jpg'],
        qualityScoreByIndex: const {0: 0.2, 1: 0.9},
      );
      final mediaId = await seedItem();
      await queue.enqueue(kind: 'ai', mediaId: mediaId);
      await buildWorker().drain();
      expect(fetched.single, 'https://x/b.jpg');
    });

    test('an empty result retries rather than failing', () async {
      api.result = ParallelGenerationResult(imageUrlsBySlot: const ['']);
      final mediaId = await seedItem();
      final job = await queue.enqueue(kind: 'ai', mediaId: mediaId);
      await buildWorker().drain();

      final reloaded = await queue.findById(job.id);
      expect(reloaded!.status, PipelineJobStatus.pending);
      expect(reloaded.attempts, 1);
    });
  });

  group('mirror ordering', () {
    test('no server session defers without consuming an attempt', () async {
      final mediaId = await seedItem(sessionId: null, photoId: null);
      final job = await queue.enqueue(kind: 'ai', mediaId: mediaId);

      expect(await buildWorker().drain(), 0);
      expect(api.calls, 0);

      final reloaded = await queue.findById(job.id);
      expect(reloaded!.status, PipelineJobStatus.pending);
      expect(reloaded.attempts, 0,
          reason: 'waiting on the mirror is not this job failing');
    });

    test('a session without an uploaded photo also defers', () async {
      final mediaId = await seedItem(photoId: null);
      final job = await queue.enqueue(kind: 'ai', mediaId: mediaId);
      await buildWorker().drain();

      expect(api.calls, 0);
      expect((await queue.findById(job.id))!.attempts, 0);
    });

    test('runs as soon as the mirror lands', () async {
      final mediaId = await seedItem(sessionId: null, photoId: null);
      await queue.enqueue(kind: 'ai', mediaId: mediaId);
      final worker = buildWorker();
      await worker.drain();
      expect(api.calls, 0);

      await ledger.setRemoteIds(mediaId, sessionId: 's9', photoId: 'p9');
      // A mirror-blocked job comes back in 10s, not the 1min default — the
      // mirror is actively working and may land within seconds.
      clock += const Duration(seconds: 11).inMilliseconds;
      expect(await worker.drain(), 1);
      expect(api.lastSessionId, 's9');
    });
  });

  group('offline and configuration', () {
    test('an offline event defers instead of burning attempts', () async {
      final mediaId = await seedItem();
      final job = await queue.enqueue(kind: 'ai', mediaId: mediaId);
      await buildWorker(settings: settingsWith(offline: true)).drain();

      expect(api.calls, 0);
      final deferred = await queue.findById(job.id);
      expect(deferred!.attempts, 0);
      // An offline event should not poll every minute against a link that is
      // not coming back this session.
      expect(
        deferred.nextAttemptAtMs - clock,
        const Duration(minutes: 10).inMilliseconds,
      );
    });

    test('no configured theme fails permanently', () async {
      final mediaId = await seedItem();
      final job = await queue.enqueue(kind: 'ai', mediaId: mediaId);
      await buildWorker(settings: settingsWith(themeId: null)).drain();

      expect((await queue.findById(job.id))!.status, PipelineJobStatus.failed);
      expect(api.calls, 0);
    });

    test('a transient API error retries', () async {
      api.throwThis = ApiException('gateway', 503);
      final mediaId = await seedItem();
      final job = await queue.enqueue(kind: 'ai', mediaId: mediaId);
      await buildWorker().drain();

      final reloaded = await queue.findById(job.id);
      expect(reloaded!.status, PipelineJobStatus.pending);
      expect(reloaded.attempts, 1);
    });

    test('a client error fails without wasting the budget', () async {
      api.throwThis = ApiException('bad request', 400);
      final mediaId = await seedItem();
      final job = await queue.enqueue(kind: 'ai', mediaId: mediaId);
      await buildWorker().drain();

      expect((await queue.findById(job.id))!.status, PipelineJobStatus.failed);
    });

    test('a failed generation leaves the source printable', () async {
      api.throwThis = ApiException('bad request', 400);
      final mediaId = await seedItem();
      await queue.enqueue(kind: 'ai', mediaId: mediaId);
      await buildWorker().drain();

      final best = await ledger.bestRenditionForPrint(mediaId);
      expect(best!.kind, RenditionKind.source,
          reason: 'a failed generation costs the styling, not the photo');
    });
  });

  group('SkipAiAction', () {
    test('drops ai, cancels the job and enqueues the next step', () async {
      final mediaId = await seedItem(sessionId: null, photoId: null);
      await ledger.markSelected(mediaId, const ['ai', 'frame', 'print']);
      final aiJob = await queue.enqueue(kind: 'ai', mediaId: mediaId);

      final changed = await SkipAiAction(ledger: ledger, queue: queue)
          .apply([mediaId]);
      expect(changed, 1);

      final item = await ledger.findById(mediaId);
      expect(item!.steps, ['frame', 'print']);
      expect(item.aiSkipped, isTrue, reason: 'visible, not a silent completion');
      expect(item.currentStep, 'frame');

      expect(
        (await queue.findById(aiJob.id))!.status,
        PipelineJobStatus.cancelled,
      );
      expect(await queue.findFor(kind: 'frame', mediaId: mediaId), isNotNull);
    });

    test('an ai-only chain completes with nothing left to run', () async {
      final mediaId = await seedItem();
      await ledger.markSelected(mediaId, const ['ai']);
      await queue.enqueue(kind: 'ai', mediaId: mediaId);

      await SkipAiAction(ledger: ledger, queue: queue).apply([mediaId]);

      final item = await ledger.findById(mediaId);
      expect(item!.steps, isEmpty);
      expect(item.stage, MediaStage.done);
      expect(item.aiSkipped, isTrue);
    });

    test('applies in bulk and skips unknown ids', () async {
      final a = await seedItem();
      final b = await seedItem();
      for (final id in [a, b]) {
        await ledger.markSelected(id, const ['ai', 'print']);
        await queue.enqueue(kind: 'ai', mediaId: id);
      }
      final changed = await SkipAiAction(ledger: ledger, queue: queue)
          .apply([a, b, 'does-not-exist']);
      expect(changed, 2);
      expect((await queue.counts('print')).pending, 2);
    });

    test('an item already past ai is not rewound', () async {
      final mediaId = await seedItem();
      await ledger.markSelected(mediaId, const ['ai', 'frame', 'print']);
      await ledger.advanceStep(mediaId); // ai done
      await ledger.advanceStep(mediaId); // frame done, on print

      await SkipAiAction(ledger: ledger, queue: queue).apply([mediaId]);
      final item = await ledger.findById(mediaId);
      expect(item!.currentStep, 'print', reason: 'framing must not re-run');
    });
  });
}
