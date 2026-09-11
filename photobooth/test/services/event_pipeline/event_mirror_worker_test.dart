import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_pipeline/media_item.dart';
import 'package:photobooth/models/event_pipeline/media_rendition.dart';
import 'package:photobooth/models/event_pipeline/pipeline_job.dart';
import 'package:photobooth/services/api_service.dart';
import 'package:photobooth/services/event_pipeline/event_media_store.dart';
import 'package:photobooth/services/event_pipeline/event_mirror_worker.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_db.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_ledger.dart';
import 'package:photobooth/services/kiosk_manager.dart';
import 'package:photobooth/utils/exceptions.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manual fake by subclass-and-override, per the repo convention.
class FakeApi extends ApiService {
  int sessionCalls = 0;
  int assetCalls = 0;
  int entityCalls = 0;
  int updateCalls = 0;
  Object? sessionThrows;
  Object? assetThrows;
  String? lastAssetPrefix;
  final List<Map<String, dynamic>> entities = [];

  @override
  Future<Map<String, dynamic>> acceptTermsAndCreateSession({
    String? kioskCode,
    String? source,
    String? selectedFrameId,
    bool includeSelectedFrameId = false,
    bool groupConsentAccepted = true,
    String? clientSessionId,
  }) async {
    sessionCalls++;
    final err = sessionThrows;
    if (err != null) throw err;
    return <String, dynamic>{'id': 'sess-$sessionCalls'};
  }

  @override
  Future<void> ingestKioskAsset({
    required String kioskCode,
    required String prefix,
    required String filename,
    required List<int> bytes,
  }) async {
    assetCalls++;
    lastAssetPrefix = prefix;
    final err = assetThrows;
    if (err != null) throw err;
  }

  @override
  Future<Map<String, dynamic>> updateSession({
    required String sessionId,
    String? userImageUrl,
    String? selectedThemeId,
    bool includeSelectedFrameId = false,
    String? selectedFrameId,
    int? personCount,
    Map<String, dynamic>? framingMetadata,
  }) async {
    updateCalls++;
    return <String, dynamic>{};
  }

  @override
  Future<void> ingestKioskEntities({
    required String kioskCode,
    required List<Map<String, dynamic>> items,
  }) async {
    entityCalls++;
    entities.addAll(items);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory mediaDir;
  late EventPipelineDb db;
  late EventPipelineLedger ledger;
  late EventMediaStore mediaStore;
  late FakeApi api;
  var ids = 0;
  var clock = 1000;
  var enabled = true;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await KioskManager().setKioskCode('K1');
    root = await Directory.systemTemp.createTemp('fz_evp_mirror_');
    mediaDir = Directory('${root.path}/media')..createSync(recursive: true);
    ids = 0;
    clock = 1000;
    enabled = true;
    db = (await EventPipelineDb.open(root))!;
    ledger = EventPipelineLedger(db: db, newId: () => 'm${ids++}');
    mediaStore = EventMediaStore(resolveDirectory: () async => mediaDir);
    api = FakeApi();
  });

  tearDown(() async {
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  EventMirrorWorker buildWorker() {
    return EventMirrorWorker(
      db: db,
      ledger: ledger,
      mediaStore: mediaStore,
      api: api,
      enabled: () => enabled,
      nowMs: () => clock,
      newId: () => 'u${ids++}',
    );
  }

  Future<String> seedItem({bool withRendition = true}) async {
    final result = await ledger.insertIfNew(
      source: MediaSource.sdCard,
      sourceRef: 'VOL:DCIM/${ids}A.JPG:1:2',
      contentKey: 'ck-$ids',
      eventId: 'EVT1',
    );
    if (withRendition) {
      final path = 'EVT1/${result.item.id}-source.jpg';
      await mediaStore.putBytes(path, [1, 2, 3, 4]);
      await ledger.putRendition(MediaRendition(
        mediaId: result.item.id,
        kind: RenditionKind.source,
        path: path,
        createdAtMs: 1,
      ));
    }
    return result.item.id;
  }

  group('ordering', () {
    test('session runs first and records the remote id', () async {
      final mediaId = await seedItem();
      final worker = buildWorker();
      await worker.enqueueItem(mediaId);
      await worker.drainUntilIdle();

      expect(api.sessionCalls, 1);
      final item = await ledger.findById(mediaId);
      expect(item!.remoteSessionId, 'sess-1');
      expect(item.remotePhotoId, isNotNull);
    });

    test('the asset stage attaches the image and unblocks AI', () async {
      final mediaId = await seedItem();
      final worker = buildWorker();
      await worker.enqueueItem(mediaId);
      await worker.drainUntilIdle();

      expect(api.assetCalls, 1);
      expect(api.updateCalls, 1);
      expect(api.lastAssetPrefix, 'event-originals/EVT1');

      // Both ids present is exactly the AI worker's precondition.
      final item = await ledger.findById(mediaId);
      expect(item!.remoteSessionId, isNotNull);
      expect(item.remotePhotoId, isNotNull);
    });

    test('an asset never precedes its session', () async {
      api.sessionThrows = ApiException('offline');
      final mediaId = await seedItem();
      final worker = buildWorker();
      await worker.enqueueItem(mediaId);
      await worker.drain();

      expect(api.sessionCalls, 1);
      expect(api.assetCalls, 0, reason: 'no session, so nothing to attach to');
    });

    test('an item with no stored rendition defers the asset stage', () async {
      final mediaId = await seedItem(withRendition: false);
      final worker = buildWorker();
      await worker.enqueueItem(mediaId);
      await worker.drainUntilIdle();

      expect(api.sessionCalls, 1);
      expect(api.assetCalls, 0);
      final counts = await worker.counts();
      expect(counts[PipelineJobStatus.failed] ?? 0, 0,
          reason: 'waiting for a derivative is not a failure');
    });

    test('the row stage mirrors the stage for logging', () async {
      final mediaId = await seedItem();
      final worker = buildWorker();
      await worker.enqueueItem(mediaId);
      await worker.drainUntilIdle();

      expect(api.entityCalls, 1);
      expect(api.entities.single['entityType'], 'event_media_item');
      expect(api.entities.single['entityId'], mediaId);
    });
  });

  group('resilience', () {
    test('is idempotent — a repeat enqueue does not duplicate work', () async {
      final mediaId = await seedItem();
      final worker = buildWorker();
      await worker.enqueueItem(mediaId);
      await worker.enqueueItem(mediaId);
      await worker.drainUntilIdle();
      expect(api.sessionCalls, 1);
    });

    test('a completed session is not created twice after a restart', () async {
      final mediaId = await seedItem();
      final worker = buildWorker();
      await worker.enqueueItem(mediaId);
      await worker.drainUntilIdle();

      // Re-queue the whole chain as a crash-recovery path would.
      await db.database.update(
        'evp_upload_queue',
        {'status': PipelineJobStatus.pending, 'next_attempt_at_ms': 0},
        where: 'media_id = ?',
        whereArgs: [mediaId],
      );
      await worker.drainUntilIdle();
      expect(api.sessionCalls, 1, reason: 'the remote id already exists');
    });

    test('a transient failure retries with backoff', () async {
      api.sessionThrows = ApiException('gateway', 503);
      final mediaId = await seedItem();
      final worker = buildWorker();
      await worker.enqueueItem(mediaId);
      await worker.drain();

      final rows = await db.database.query(
        'evp_upload_queue',
        where: 'kind = ? AND media_id = ?',
        whereArgs: ['session', mediaId],
      );
      expect(rows.single['status'], PipelineJobStatus.pending);
      expect(rows.single['attempts'], 1);
      expect(rows.single['next_attempt_at_ms'], greaterThan(clock));
    });

    test('a client error fails without exhausting the budget', () async {
      api.sessionThrows = ApiException('bad request', 400);
      final mediaId = await seedItem();
      final worker = buildWorker();
      await worker.enqueueItem(mediaId);
      await worker.drain();

      final rows = await db.database.query(
        'evp_upload_queue',
        where: 'kind = ? AND media_id = ?',
        whereArgs: ['session', mediaId],
      );
      expect(rows.single['status'], PipelineJobStatus.failed);
      expect(rows.single['attempts'], 1);
    });

    test('a deleted media item drops its queue rows rather than retrying',
        () async {
      final worker = buildWorker();
      await worker.enqueueItem('gone');
      await worker.drainUntilIdle();
      final counts = await worker.counts();
      expect(counts[PipelineJobStatus.done], 3);
      expect(api.sessionCalls, 0);
    });
  });

  group('gating', () {
    test('does nothing when mirroring is disabled', () async {
      enabled = false;
      final mediaId = await seedItem();
      final worker = buildWorker();
      await worker.enqueueItem(mediaId);
      expect(await worker.drain(), 0);
      expect(api.sessionCalls, 0);
    });

    test('does nothing without a bound kiosk code', () async {
      await KioskManager().clearKioskCode();
      final mediaId = await seedItem();
      final worker = buildWorker();
      await worker.enqueueItem(mediaId);
      expect(await worker.drain(), 0);
      expect(api.sessionCalls, 0);
    });

    test('start is idempotent and stop halts the timer', () {
      final worker = buildWorker();
      expect(worker.isRunning, isFalse);
      worker.start(interval: const Duration(minutes: 5));
      expect(worker.isRunning, isTrue);
      worker.start(interval: const Duration(minutes: 5));
      worker.stop();
      expect(worker.isRunning, isFalse);
    });
  });

  test('batches are small so a venue link is not saturated', () async {
    // 3,000 photos means 3,000 session creations; bursting them mid-event would
    // swamp the link the guests are also using.
    expect(buildWorker().batchLimit, lessThanOrEqualTo(4));
  });
}
