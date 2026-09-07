import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_pipeline/event_pipeline_settings.dart';
import 'package:photobooth/models/event_pipeline/event_print_size.dart';
import 'package:photobooth/models/event_pipeline/media_item.dart';
import 'package:photobooth/models/event_pipeline/media_rendition.dart';
import 'package:photobooth/models/kiosk_frame_model.dart';
import 'package:photobooth/services/api_service.dart';
import 'package:photobooth/services/event_pipeline/event_frame_cache.dart';
import 'package:photobooth/services/event_pipeline/event_media_store.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_db.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_ledger.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_queue.dart';
import 'package:photobooth/services/event_pipeline/frame_compositor.dart';
import 'package:photobooth/services/event_pipeline/frame_job_worker.dart';
import 'package:photobooth/services/event_pipeline/ingest/folder_ingest_source.dart';
import 'package:photobooth/services/event_pipeline/ingest/image_downscaler.dart';
import 'package:photobooth/services/event_pipeline/ingest/ingest_worker.dart';
import 'package:photobooth/services/event_pipeline/print_job_worker.dart';
import 'package:photobooth/services/event_pipeline/printer_status_reader.dart';
import 'package:photobooth/models/event_pipeline/printer_consumables.dart';

class StubApi extends ApiService {
  StubApi(this.frames);
  final List<KioskFrameModel> frames;

  @override
  Future<List<KioskFrameModel>> getKioskFrames() async => frames;
}

class StubDownscaler implements ImageDownscaler {
  @override
  Future<DownscaleResult> downscale({
    required String sourceUri,
    required int targetShortSide,
    int maxLongSide = 4096,
    int quality = 88,
  }) async {
    return DownscaleResult(
      bytes: Uint8List.fromList(List<int>.filled(1024, 4)),
      width: targetShortSide * 3 ~/ 2,
      height: targetShortSide,
    );
  }
}

class StubCompositor implements FrameCompositor {
  int calls = 0;

  @override
  Future<CompositeResult> composite({
    required String photoPath,
    required String? framePath,
    required EventPrintSize size,
    int quality = 88,
  }) async {
    calls++;
    return CompositeResult(
      bytes: Uint8List.fromList(List<int>.filled(2048, 6)),
      width: size.width,
      height: size.height,
    );
  }
}

class ReadyStatus extends PrinterStatusReader {
  @override
  Future<PrinterConsumables> read() async => const PrinterConsumables(
        code: 0,
        readiness: PrinterReadiness.ready,
        label: 'Idle',
      );
}

void main() {
  late Directory root;
  late Directory card;
  late Directory mediaDir;
  late EventPipelineDb db;
  late EventPipelineLedger ledger;
  late EventPipelineQueue queue;
  late EventMediaStore mediaStore;
  var ids = 0;

  /// An AI-off, frame-on, auto-print event: the offline milestone.
  final settings = EventPipelineSettings(
    pipelineEnabled: true,
    offlineMode: true,
    aiEnabled: false,
    frameEnabled: true,
    frameId: 'frame-1',
    autoPrint: true,
    defaultCopies: 1,
    printSize: 's4x6',
    qualityFactor: 1.0,
    mirrorEnabled: false,
    scanFolders: const ['DCIM'],
  );

  Future<void> writePhoto(String relativePath, int fill) async {
    final file = File('${card.path}/$relativePath');
    await file.parent.create(recursive: true);
    final bytes = Uint8List(4096);
    bytes[0] = 0xFF;
    bytes[1] = 0xD8;
    for (var i = 2; i < bytes.length; i++) {
      bytes[i] = fill;
    }
    await file.writeAsBytes(bytes);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fz_evp_e2e_');
    card = Directory('${root.path}/card')..createSync(recursive: true);
    mediaDir = Directory('${root.path}/media')..createSync(recursive: true);
    ids = 0;
    db = (await EventPipelineDb.open(root))!;
    ledger = EventPipelineLedger(db: db, newId: () => 'm${ids++}');
    queue = EventPipelineQueue(db: db, newId: () => 'j${ids++}');
    mediaStore = EventMediaStore(resolveDirectory: () async => mediaDir);
  });

  tearDown(() async {
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('an offline AI-off event runs ingest → frame → print end to end',
      () async {
    // --- Setup, while the link is still up: cache the frame artwork.
    final frameCache = EventFrameCache(
      db: db,
      mediaStore: mediaStore,
      api: StubApi(const [
        KioskFrameModel(id: 'frame-1', name: 'Priya', overlayUrl: '/f1.png'),
      ]),
      fetchBytes: (_) async => Uint8List.fromList(List<int>.filled(64, 3)),
    );
    final frameStatus = await frameCache.refresh(
      eventId: 'EVT1',
      selectedFrameId: 'frame-1',
    );
    expect(frameStatus.selectedIsCached, isTrue,
        reason: 'framing cannot run offline without this');

    // --- The link is now irrelevant. Everything below is local.
    await writePhoto('DCIM/100CANON/IMG_0001.JPG', 1);
    await writePhoto('DCIM/100CANON/IMG_0002.JPG', 2);
    await writePhoto('DCIM/100CANON/IMG_0003.CR3', 3); // RAW, must be skipped

    final source = FolderIngestSource(
      directory: card,
      id: 'VOL-1',
      sourceKind: MediaSource.sdCard,
    );
    final ingest = IngestWorker(
      ledger: ledger,
      mediaStore: mediaStore,
      downscaler: StubDownscaler(),
    );

    // --- Scan.
    final scan = await ingest.scan(source, scanFolders: const ['DCIM']);
    expect(scan.newCandidates, hasLength(2));
    expect(scan.skippedRaw, 1);

    // --- Import.
    final report = await ingest.import(
      source,
      scan.newCandidates,
      settings: settings,
      eventId: 'EVT1',
    );
    expect(report.imported, 2);

    // --- Select: freeze the chain and enqueue the first step.
    for (final mediaId in report.mediaIds) {
      final item = await ledger.markSelected(mediaId, settings.resolveSteps());
      expect(item!.steps, ['frame', 'print']);
      await queue.enqueue(
        kind: item.currentStep!,
        mediaId: mediaId,
        eventId: 'EVT1',
      );
    }

    // --- Frame.
    final compositor = StubCompositor();
    final frameWorker = FrameJobWorker(
      queue: queue,
      ledger: ledger,
      frameCache: frameCache,
      mediaStore: mediaStore,
      compositor: compositor,
      settings: () => settings,
    );
    expect(await frameWorker.drainUntilIdle(), 2);
    expect(compositor.calls, 2);

    // --- Print. The frame worker enqueued these itself.
    final printed = <String>[];
    final printWorker = PrintJobWorker(
      queue: queue,
      ledger: ledger,
      mediaStore: mediaStore,
      statusReader: ReadyStatus(),
      settings: () => settings,
      printFn: (file, {required printSize, int quantity = 1}) async {
        printed.add(file.path);
      },
    );
    expect(await printWorker.drainUntilIdle(), 2);

    // --- Every photo reached the end, printed from its framed rendition.
    expect(printed, hasLength(2));
    for (final path in printed) {
      expect(path, endsWith('-framed.jpg'));
    }
    for (final mediaId in report.mediaIds) {
      final item = await ledger.findById(mediaId);
      expect(item!.stage, MediaStage.done);
      expect(item.isChainComplete, isTrue);
      final renditions = await ledger.renditionsFor(mediaId);
      expect(
        renditions.map((r) => r.kind).toSet(),
        {RenditionKind.source, RenditionKind.framed},
      );
    }

    // --- A rescan of the same card imports nothing.
    final rescan = await ingest.scan(source, scanFolders: const ['DCIM']);
    expect(rescan.newCandidates, isEmpty);
    expect(rescan.alreadyImported, 2);
  });

  test('the chain survives a restart mid-queue', () async {
    await writePhoto('DCIM/A.JPG', 1);
    final source = FolderIngestSource(
      directory: card,
      id: 'VOL-1',
      sourceKind: MediaSource.sdCard,
    );
    final ingest = IngestWorker(
      ledger: ledger,
      mediaStore: mediaStore,
      downscaler: StubDownscaler(),
    );
    final scan = await ingest.scan(source, scanFolders: const ['DCIM']);
    final report = await ingest.import(
      source,
      scan.newCandidates,
      settings: settings,
      eventId: 'EVT1',
    );
    final mediaId = report.mediaIds.single;
    await ledger.markSelected(mediaId, const ['print']);
    await queue.enqueue(kind: 'print', mediaId: mediaId, eventId: 'EVT1');

    // Simulate a process kill: drop every in-memory object and reopen.
    await db.close();
    final reopened = (await EventPipelineDb.open(root))!;
    addTearDown(reopened.close);
    final ledger2 = EventPipelineLedger(db: reopened);
    final queue2 = EventPipelineQueue(db: reopened);

    final item = await ledger2.findById(mediaId);
    expect(item!.steps, ['print'], reason: 'the frozen chain is durable');
    expect(await queue2.findFor(kind: 'print', mediaId: mediaId), isNotNull);

    final printed = <String>[];
    final worker = PrintJobWorker(
      queue: queue2,
      ledger: ledger2,
      mediaStore: mediaStore,
      statusReader: ReadyStatus(),
      settings: () => settings,
      printFn: (XFile file, {required String printSize, int quantity = 1}) async {
        printed.add(file.path);
      },
    );
    expect(await worker.drainUntilIdle(), 1);
    expect(printed, hasLength(1));
  });
}
