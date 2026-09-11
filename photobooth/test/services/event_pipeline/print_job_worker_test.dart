import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_pipeline/event_pipeline_settings.dart';
import 'package:photobooth/models/event_pipeline/media_item.dart';
import 'package:photobooth/models/event_pipeline/media_rendition.dart';
import 'package:photobooth/models/event_pipeline/pipeline_job.dart';
import 'package:photobooth/models/event_pipeline/printer_consumables.dart';
import 'package:photobooth/services/event_pipeline/event_media_store.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_db.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_ledger.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_queue.dart';
import 'package:photobooth/services/event_pipeline/print_job_worker.dart';
import 'package:photobooth/services/event_pipeline/printer_status_reader.dart';

/// Manual fake by subclass-and-override, per the repo convention.
class FakeStatusReader extends PrinterStatusReader {
  FakeStatusReader({this.readings = const []});

  /// Consumed in order; the last value repeats once exhausted.
  List<PrinterConsumables> readings;
  int calls = 0;

  @override
  Future<PrinterConsumables> read() async {
    if (readings.isEmpty) {
      calls++;
      return const PrinterConsumables(
        code: 0,
        readiness: PrinterReadiness.ready,
        label: 'Idle',
      );
    }
    final index = calls < readings.length ? calls : readings.length - 1;
    calls++;
    return readings[index];
  }
}

EventPipelineSettings settingsWith({
  int copies = 1,
  String printSize = 's4x6',
}) {
  return EventPipelineSettings(
    pipelineEnabled: true,
    offlineMode: true,
    aiEnabled: false,
    frameEnabled: false,
    autoPrint: true,
    defaultCopies: copies,
    printSize: printSize,
    qualityFactor: 1.0,
    mirrorEnabled: false,
    scanFolders: const ['DCIM'],
  );
}

const ready = PrinterConsumables(
  code: 0,
  readiness: PrinterReadiness.ready,
  label: 'Idle',
);
const ribbonOut = PrinterConsumables(
  code: PrinterConsumables.ribbonEnd,
  readiness: PrinterReadiness.needsAttention,
  label: 'Ribbon end — replace ribbon',
);

void main() {
  late Directory root;
  late Directory mediaDir;
  late EventPipelineDb db;
  late EventPipelineLedger ledger;
  late EventPipelineQueue queue;
  late EventMediaStore mediaStore;
  var ids = 0;

  final printed = <({String path, String size, int quantity})>[];
  var printShouldThrow = false;

  Future<void> fakePrint(
    XFile file, {
    required String printSize,
    int quantity = 1,
  }) async {
    printed.add((path: file.path, size: printSize, quantity: quantity));
    if (printShouldThrow) throw StateError('printer stopped');
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fz_evp_print_');
    mediaDir = Directory('${root.path}/media')..createSync(recursive: true);
    ids = 0;
    printed.clear();
    printShouldThrow = false;
    db = (await EventPipelineDb.open(root))!;
    ledger = EventPipelineLedger(db: db, newId: () => 'm${ids++}');
    queue = EventPipelineQueue(db: db, newId: () => 'j${ids++}');
    mediaStore = EventMediaStore(resolveDirectory: () async => mediaDir);
  });

  tearDown(() async {
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<String> seedItem({String kind = RenditionKind.source}) async {
    final result = await ledger.insertIfNew(
      source: MediaSource.sdCard,
      sourceRef: 'VOL:DCIM/${ids}A.JPG:100:200',
      contentKey: 'ck-$ids',
      eventId: 'EVT1',
    );
    final path = 'EVT1/${result.item.id}-$kind.jpg';
    await mediaStore.putBytes(path, [1, 2, 3]);
    await ledger.putRendition(MediaRendition(
      mediaId: result.item.id,
      kind: kind,
      path: path,
      createdAtMs: 1,
    ));
    return result.item.id;
  }

  PrintJobWorker buildWorker({
    FakeStatusReader? status,
    EventPipelineSettings? settings,
  }) {
    return PrintJobWorker(
      queue: queue,
      ledger: ledger,
      mediaStore: mediaStore,
      printFn: fakePrint,
      settings: () => settings ?? settingsWith(),
      statusReader: status ?? FakeStatusReader(),
    );
  }

  group('PrinterConsumables.classify', () {
    test('idle, printing and unreadable are printable', () {
      for (final code in [-1, 0, 1]) {
        expect(PrinterConsumables.classify(code), PrinterReadiness.ready);
      }
    });

    test('cooling and standby are transient', () {
      for (final code in [500, 510, 900]) {
        expect(PrinterConsumables.classify(code), PrinterReadiness.busy);
      }
    });

    test('consumable and jam faults need attention', () {
      for (final code in [1000, 1010, 1100, 1200, 1300, 1400, 1500]) {
        expect(
          PrinterConsumables.classify(code),
          PrinterReadiness.needsAttention,
          reason: '$code should pause the queue',
        );
      }
    });

    test('a print data error is this job\'s fault, not the printer\'s', () {
      // Pausing the whole queue for one malformed image would stall the event
      // behind a single photo.
      expect(
        PrinterConsumables.classify(PrinterConsumables.printDataError),
        PrinterReadiness.badJob,
      );
    });

    test('an unrecognised error code errs toward stopping', () {
      expect(PrinterConsumables.classify(1234), PrinterReadiness.needsAttention);
    });

    test('a missing status map reads as offline', () {
      expect(
        PrinterConsumables.fromStatusMap(null).readiness,
        PrinterReadiness.offline,
      );
    });

    test('parses a real status payload', () {
      final parsed = PrinterConsumables.fromStatusMap(const {
        'name': 'DS-RX1',
        'status': 1200,
        'statusLabel': 'Ribbon end — replace ribbon',
        'ready': false,
      });
      expect(parsed.shouldPause, isTrue);
      expect(parsed.reason, 'Ribbon end — replace ribbon');
      expect(parsed.name, 'DS-RX1');
    });
  });

  group('printing', () {
    test('prints the stored image and completes the item', () async {
      final mediaId = await seedItem();
      await ledger.markSelected(mediaId, const ['print']);
      await queue.enqueue(kind: 'print', mediaId: mediaId, eventId: 'EVT1');

      expect(await buildWorker().drain(), 1);
      expect(printed, hasLength(1));
      expect(printed.single.size, 's4x6');

      final item = await ledger.findById(mediaId);
      expect(item!.stage, MediaStage.done);
      expect(item.isChainComplete, isTrue);
    });

    test('prints the framed rendition in preference to the source', () async {
      final mediaId = await seedItem();
      await mediaStore.putBytes('EVT1/$mediaId-framed.jpg', [9]);
      await ledger.putRendition(MediaRendition(
        mediaId: mediaId,
        kind: RenditionKind.framed,
        path: 'EVT1/$mediaId-framed.jpg',
        createdAtMs: 2,
      ));
      await queue.enqueue(kind: 'print', mediaId: mediaId);
      await buildWorker().drain();
      expect(printed.single.path, endsWith('-framed.jpg'));
    });

    test('falls back to the source when framing never produced output',
        () async {
      final mediaId = await seedItem();
      await queue.enqueue(kind: 'print', mediaId: mediaId);
      await buildWorker().drain();
      expect(printed.single.path, endsWith('-source.jpg'));
    });

    test('copies come from settings', () async {
      final mediaId = await seedItem();
      await queue.enqueue(kind: 'print', mediaId: mediaId);
      await buildWorker(settings: settingsWith(copies: 3)).drain();
      expect(printed.single.quantity, 3);
    });

    test('a payload copy count wins over later settings changes', () async {
      final mediaId = await seedItem();
      await queue.enqueue(
        kind: 'print',
        mediaId: mediaId,
        payload: const {'copies': 2},
      );
      await buildWorker(settings: settingsWith(copies: 9)).drain();
      expect(printed.single.quantity, 2);
    });

    test('an item with no stored image fails rather than printing nothing',
        () async {
      final result = await ledger.insertIfNew(
        source: MediaSource.sdCard,
        sourceRef: 'VOL:none:1:1',
        contentKey: 'ck-none',
      );
      await queue.enqueue(kind: 'print', mediaId: result.item.id);
      await buildWorker().drain();
      expect((await queue.counts('print')).failed, 1);
      expect(printed, isEmpty);
    });
  });

  group('consumables', () {
    test('ribbon out pauses the queue instead of burning attempts', () async {
      for (var i = 0; i < 3; i++) {
        final mediaId = await seedItem();
        await queue.enqueue(kind: 'print', mediaId: mediaId);
      }
      final worker = buildWorker(
        status: FakeStatusReader(readings: const [ribbonOut]),
      );
      await worker.drain();

      final counts = await queue.counts('print');
      expect(counts.paused, 3, reason: 'every open print job is held');
      expect(counts.failed, 0, reason: 'a media change is not a failure');
      expect(printed, isEmpty);
    });

    test('reloading resumes the queue with no restart', () async {
      final mediaId = await seedItem();
      await queue.enqueue(kind: 'print', mediaId: mediaId);
      await buildWorker(
        status: FakeStatusReader(readings: const [ribbonOut]),
      ).drain();
      expect((await queue.counts('print')).paused, 1);

      await queue.resumeKind('print');
      expect(await buildWorker().drainUntilIdle(), 1);
      expect(printed, hasLength(1));
    });

    test('a mid-print failure re-reads status and pauses on ribbon out',
        () async {
      printShouldThrow = true;
      final mediaId = await seedItem();
      await queue.enqueue(kind: 'print', mediaId: mediaId);

      // Ready before the job, ribbon out after — the media ran out mid-print.
      await buildWorker(
        status: FakeStatusReader(readings: const [ready, ribbonOut]),
      ).drain();

      final counts = await queue.counts('print');
      expect(counts.paused, 1);
      expect(counts.failed, 0);
    });

    test('a mid-print failure with a healthy printer retries', () async {
      printShouldThrow = true;
      final mediaId = await seedItem();
      final job = await queue.enqueue(kind: 'print', mediaId: mediaId);
      await buildWorker(status: FakeStatusReader(readings: const [ready]))
          .drain();

      final reloaded = await queue.findById(job.id);
      expect(reloaded!.status, PipelineJobStatus.pending);
      expect(reloaded.attempts, 1);
    });

    test('a cooling printer defers without consuming an attempt', () async {
      final mediaId = await seedItem();
      final job = await queue.enqueue(kind: 'print', mediaId: mediaId);
      await buildWorker(
        status: FakeStatusReader(
          readings: const [
            PrinterConsumables(
              code: 500,
              readiness: PrinterReadiness.busy,
              label: 'Cooling print head',
            ),
          ],
        ),
      ).drain();

      final reloaded = await queue.findById(job.id);
      expect(reloaded!.attempts, 0, reason: 'cooling clears itself');
      expect(reloaded.status, PipelineJobStatus.pending);
      expect(printed, isEmpty);
    });

    test('no printer defers so an offline event keeps its queue', () async {
      final mediaId = await seedItem();
      final job = await queue.enqueue(kind: 'print', mediaId: mediaId);
      await buildWorker(
        status: FakeStatusReader(readings: const [PrinterConsumables.offline]),
      ).drain();

      final reloaded = await queue.findById(job.id);
      expect(reloaded!.status, PipelineJobStatus.pending);
      expect(reloaded.attempts, 0);
    });

    test('a print data error fails only that job', () async {
      final first = await seedItem();
      final second = await seedItem();
      await queue.enqueue(kind: 'print', mediaId: first);
      await queue.enqueue(kind: 'print', mediaId: second);

      await buildWorker(
        status: FakeStatusReader(
          readings: const [
            PrinterConsumables(
              code: PrinterConsumables.printDataError,
              readiness: PrinterReadiness.badJob,
              label: 'Print data error',
            ),
          ],
        ),
      ).drain(limit: 1);

      final counts = await queue.counts('print');
      expect(counts.failed, 1);
      expect(counts.paused, 0, reason: 'the queue keeps going');
      expect(counts.pending, 1);
    });
  });

  group('PrinterStatusReader', () {
    test('NO_PRINTER reads as offline', () async {
      const channel = MethodChannel(PrinterStatusReader.channelName);
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'NO_PRINTER');
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final result = await PrinterStatusReader().read();
      expect(result.readiness, PrinterReadiness.offline);
    });

    test('an unreadable status stays printable rather than blocking', () async {
      const channel = MethodChannel(PrinterStatusReader.channelName);
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'STATUS_ERROR', message: 'timeout');
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      // Some TV USB hosts fail the status query routinely; DnpUsbPrinter treats
      // that as printable and so must we, or nothing ever prints on those boxes.
      final result = await PrinterStatusReader().read();
      expect(result.canPrint, isTrue);
    });
  });
}
