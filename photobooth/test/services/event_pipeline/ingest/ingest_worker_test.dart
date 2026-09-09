import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_pipeline/event_pipeline_settings.dart';
import 'package:photobooth/models/event_pipeline/media_item.dart';
import 'package:photobooth/models/event_pipeline/media_rendition.dart';
import 'package:photobooth/services/event_pipeline/event_media_store.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_db.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_ledger.dart';
import 'package:photobooth/services/event_pipeline/ingest/folder_ingest_source.dart';
import 'package:photobooth/services/event_pipeline/ingest/image_downscaler.dart';
import 'package:photobooth/services/event_pipeline/ingest/ingest_source.dart';
import 'package:photobooth/services/event_pipeline/ingest/ingest_worker.dart';

/// Manual fake by subclass-and-override, per the repo's convention.
class FakeDownscaler implements ImageDownscaler {
  FakeDownscaler({
    this.failOn = const <String>{},
    this.vanishFrom,
  });

  final Set<String> failOn;

  /// Once this many downscales have been attempted, every later one fails the
  /// way a pulled card fails: the native side cannot open the item at all.
  final int? vanishFrom;

  final List<int> requestedShortSides = <int>[];
  int calls = 0;

  @override
  Future<DownscaleResult> downscale({
    required String sourceUri,
    required int targetShortSide,
    int maxLongSide = 4096,
    int quality = 88,
  }) async {
    calls++;
    requestedShortSides.add(targetShortSide);
    if (vanishFrom != null && calls > vanishFrom!) {
      // Exactly what EventImageDownscaler.kt reports when the volume has gone.
      throw PlatformException(
        code: 'downscale_failed',
        message: 'java.io.FileNotFoundException: $sourceUri: '
            'open failed: ENOENT (No such file or directory)',
      );
    }
    if (failOn.any(sourceUri.endsWith)) {
      throw StateError('cannot decode $sourceUri');
    }
    // Stand-in for a real encode: a small deterministic buffer.
    return DownscaleResult(
      bytes: Uint8List.fromList(List<int>.filled(2048, 7)),
      width: targetShortSide * 3 ~/ 2,
      height: targetShortSide,
    );
  }
}

EventPipelineSettings settingsWith({double qualityFactor = 1.0}) {
  return EventPipelineSettings(
    pipelineEnabled: true,
    offlineMode: false,
    aiEnabled: false,
    frameEnabled: false,
    autoPrint: true,
    defaultCopies: 1,
    printSize: 's4x6',
    qualityFactor: qualityFactor,
    mirrorEnabled: false,
    scanFolders: const ['DCIM'],
  );
}

void main() {
  late Directory root;
  late Directory card;
  late Directory mediaDir;
  late EventPipelineDb db;
  late EventPipelineLedger ledger;
  late EventMediaStore mediaStore;
  late FakeDownscaler downscaler;
  late IngestWorker worker;
  var ids = 0;

  /// Minimal JPEG: SOI marker plus filler, so magic-byte checks behave.
  Future<File> writePhoto(String relativePath, {int size = 200000, int fill = 3}) async {
    final file = File('${card.path}/$relativePath');
    await file.parent.create(recursive: true);
    final bytes = Uint8List(size);
    bytes[0] = 0xFF;
    bytes[1] = 0xD8;
    for (var i = 2; i < size; i++) {
      bytes[i] = fill;
    }
    await file.writeAsBytes(bytes);
    return file;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fz_evp_ingest_');
    card = Directory('${root.path}/card')..createSync(recursive: true);
    mediaDir = Directory('${root.path}/media')..createSync(recursive: true);
    ids = 0;
    db = (await EventPipelineDb.open(root))!;
    ledger = EventPipelineLedger(db: db, newId: () => 'm${ids++}');
    mediaStore = EventMediaStore(resolveDirectory: () async => mediaDir);
    downscaler = FakeDownscaler();
    worker = IngestWorker(
      ledger: ledger,
      mediaStore: mediaStore,
      downscaler: downscaler,
      nowMs: () => 1,
    );
  });

  tearDown(() async {
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  FolderIngestSource source() => FolderIngestSource(
        directory: card,
        id: 'VOL-1',
        sourceKind: MediaSource.sdCard,
      );

  group('scan', () {
    test('finds photos under DCIM and ignores other folders', () async {
      await writePhoto('DCIM/100CANON/IMG_0001.JPG');
      await writePhoto('DCIM/100CANON/IMG_0002.JPG', fill: 4);
      await writePhoto('Pictures/screenshot.jpg', fill: 5);

      final result = await worker.scan(source(), scanFolders: const ['DCIM']);
      expect(result.newCandidates, hasLength(2));
      expect(result.outsideScanFolders, 1);
    });

    test('skips macOS AppleDouble stubs', () async {
      await writePhoto('DCIM/100CANON/IMG_0001.JPG');
      await writePhoto('DCIM/100CANON/._IMG_0001.JPG', size: 4096, fill: 9);

      final result = await worker.scan(source(), scanFolders: const ['DCIM']);
      expect(result.newCandidates, hasLength(1));
      expect(result.newCandidates.single.displayName, 'IMG_0001.JPG');
    });

    test('a missing directory scans empty rather than throwing', () async {
      final gone = FolderIngestSource(
        directory: Directory('${root.path}/nope'),
        id: 'VOL-X',
      );
      final result = await worker.scan(gone, scanFolders: const ['DCIM']);
      expect(result.newCandidates, isEmpty);
    });
  });

  group('import', () {
    test('imports new photos and stores a derivative for each', () async {
      await writePhoto('DCIM/100CANON/IMG_0001.JPG');
      await writePhoto('DCIM/100CANON/IMG_0002.JPG', fill: 4);

      final scan = await worker.scan(source(), scanFolders: const ['DCIM']);
      final report = await worker.import(
        source(),
        scan.newCandidates,
        settings: settingsWith(),
        eventId: 'EVT1',
      );

      expect(report.imported, 2);
      expect(report.duplicates, 0);
      expect(report.failed, 0);
      expect(downscaler.calls, 2);

      for (final id in report.mediaIds) {
        final rendition = await ledger.bestRenditionForPrint(id);
        expect(rendition, isNotNull);
        expect(rendition!.kind, RenditionKind.source);
        expect(await mediaStore.getFile(rendition.path), isNotNull);
      }
    });

    test('a rescan after import finds nothing new', () async {
      await writePhoto('DCIM/100CANON/IMG_0001.JPG');
      final first = await worker.scan(source(), scanFolders: const ['DCIM']);
      await worker.import(source(), first.newCandidates,
          settings: settingsWith());

      final second = await worker.scan(source(), scanFolders: const ['DCIM']);
      expect(second.newCandidates, isEmpty);
      expect(second.alreadyImported, 1);
    });

    test('a reformatted card re-imports the same filename', () async {
      await writePhoto('DCIM/100CANON/IMG_0001.JPG', size: 200000, fill: 3);
      final first = await worker.scan(source(), scanFolders: const ['DCIM']);
      await worker.import(source(), first.newCandidates,
          settings: settingsWith());

      // Same path, genuinely different photograph after a format.
      await writePhoto('DCIM/100CANON/IMG_0001.JPG', size: 310000, fill: 8);
      final second = await worker.scan(source(), scanFolders: const ['DCIM']);
      expect(second.newCandidates, hasLength(1),
          reason: 'size and mtime differ, so this is not the old photo');

      final report = await worker.import(source(), second.newCandidates,
          settings: settingsWith());
      expect(report.imported, 1);
    });

    test('the same photo by a second route dedupes on the content key',
        () async {
      await writePhoto('DCIM/100CANON/IMG_0001.JPG');
      final scan = await worker.scan(source(), scanFolders: const ['DCIM']);
      await worker.import(source(), scan.newCandidates,
          settings: settingsWith());

      // Byte-identical file, different path and a different source kind.
      await writePhoto('DCIM/101CANON/COPY.JPG');
      final second = FolderIngestSource(
        directory: card,
        id: 'VOL-1',
        sourceKind: MediaSource.gallery,
      );
      final rescan = await worker.scan(second, scanFolders: const ['DCIM']);
      final report = await worker.import(second, rescan.newCandidates,
          settings: settingsWith());

      expect(report.duplicates, greaterThanOrEqualTo(1));
      final ingested = await ledger.listByStage(MediaStage.ingested);
      expect(ingested, hasLength(1), reason: 'one photograph, one row');
    });

    test('quality factor drives the downscale target', () async {
      await writePhoto('DCIM/A.JPG');
      final scan = await worker.scan(source(), scanFolders: const ['DCIM']);
      await worker.import(
        source(),
        scan.newCandidates,
        settings: settingsWith(qualityFactor: 1.5),
      );
      expect(downscaler.requestedShortSides.single, 2880);
    });

    test('a downscale failure marks the item failed, not imported', () async {
      await writePhoto('DCIM/A.JPG');
      await writePhoto('DCIM/B.JPG', fill: 4);
      worker = IngestWorker(
        ledger: ledger,
        mediaStore: mediaStore,
        downscaler: FakeDownscaler(failOn: {'B.JPG'}),
        nowMs: () => 1,
      );

      final scan = await worker.scan(source(), scanFolders: const ['DCIM']);
      final report = await worker.import(source(), scan.newCandidates,
          settings: settingsWith());

      expect(report.imported, 1);
      expect(report.failed, 1);
      final failed = await ledger.listByStage(MediaStage.failed);
      expect(failed, hasLength(1));
      expect(failed.single.originalFilename, 'B.JPG');
      expect(failed.single.lastError, isNotNull);
    });

    test('progress is reported for every candidate', () async {
      for (var i = 0; i < 3; i++) {
        await writePhoto('DCIM/IMG_$i.JPG', fill: i + 1);
      }
      final scan = await worker.scan(source(), scanFolders: const ['DCIM']);
      final seen = <int>[];
      await worker.import(
        source(),
        scan.newCandidates,
        settings: settingsWith(),
        onProgress: (p) => seen.add(p.done),
      );
      expect(seen, [1, 2, 3]);
    });

    test('shouldContinue stops the run and leaves the ledger consistent',
        () async {
      for (var i = 0; i < 5; i++) {
        await writePhoto('DCIM/IMG_$i.JPG', fill: i + 1);
      }
      final scan = await worker.scan(source(), scanFolders: const ['DCIM']);
      var seen = 0;
      final report = await worker.import(
        source(),
        scan.newCandidates,
        settings: settingsWith(),
        shouldContinue: () async {
          seen++;
          return seen > 2 ? 'disk full' : null;
        },
      );

      expect(report.imported, 2);
      expect(report.stoppedEarly, isTrue);
      expect(report.stopReason, 'disk full');
      // Everything counted as imported is genuinely complete.
      for (final id in report.mediaIds) {
        expect(await ledger.bestRenditionForPrint(id), isNotNull);
      }
    });

    test('a card pulled mid-import rolls back rather than failing the rest',
        () async {
      for (var i = 0; i < 5; i++) {
        await writePhoto('DCIM/IMG_$i.JPG', fill: i + 1);
      }
      worker = IngestWorker(
        ledger: ledger,
        mediaStore: mediaStore,
        downscaler: FakeDownscaler(vanishFrom: 2),
        nowMs: () => 1,
      );

      final scan = await worker.scan(source(), scanFolders: const ['DCIM']);
      final report = await worker.import(source(), scan.newCandidates,
          settings: settingsWith());

      expect(report.imported, 2);
      expect(report.failed, 0, reason: 'the card going away is not 3 faults');
      expect(report.stoppedEarly, isTrue);
      expect(report.stopReason, IngestReport.cardRemovedReason);
      expect(report.stoppedOnCardRemoval, isTrue);

      expect(await ledger.listByStage(MediaStage.failed), isEmpty);
      expect(await ledger.listByStage(MediaStage.ingested), hasLength(2),
          reason: 'only the two that completed have rows');
    });

    test('the rows for photos left on the card are absent, not FAILED',
        () async {
      await writePhoto('DCIM/A.JPG');
      await writePhoto('DCIM/B.JPG', fill: 4);
      worker = IngestWorker(
        ledger: ledger,
        mediaStore: mediaStore,
        downscaler: FakeDownscaler(vanishFrom: 0),
        nowMs: () => 1,
      );

      final scan = await worker.scan(source(), scanFolders: const ['DCIM']);
      await worker.import(source(), scan.newCandidates,
          settings: settingsWith());

      expect(await ledger.knownSourceRefs(MediaSource.sdCard), isEmpty,
          reason: 'a half-written row would make the rescan report "0 new"');
    });

    test('a rescan after a card removal finds the photos new again', () async {
      for (var i = 0; i < 4; i++) {
        await writePhoto('DCIM/IMG_$i.JPG', fill: i + 1);
      }
      final interrupted = IngestWorker(
        ledger: ledger,
        mediaStore: mediaStore,
        downscaler: FakeDownscaler(vanishFrom: 1),
        nowMs: () => 1,
      );
      final first = await interrupted.scan(source(), scanFolders: const ['DCIM']);
      final firstReport = await interrupted.import(
        source(),
        first.newCandidates,
        settings: settingsWith(),
      );
      expect(firstReport.imported, 1);

      // The operator reinserts the card and scans again.
      final second = await worker.scan(source(), scanFolders: const ['DCIM']);
      expect(second.newCandidates, hasLength(3),
          reason: 'the three still on the card must be reachable');
      expect(second.alreadyImported, 1, reason: 'the finished one dedupes away');

      final report = await worker.import(source(), second.newCandidates,
          settings: settingsWith());
      expect(report.imported, 3);
      expect(await ledger.listByStage(MediaStage.ingested), hasLength(4));
    });

    test('the removal signal stops the run instead of failing every item',
        () async {
      for (var i = 0; i < 40; i++) {
        await writePhoto('DCIM/IMG_$i.JPG', fill: i + 1);
      }
      final scan = await worker.scan(source(), scanFolders: const ['DCIM']);
      var removed = false;
      final report = await worker.import(
        source(),
        scan.newCandidates,
        settings: settingsWith(),
        onProgress: (p) {
          if (p.done == 3) removed = true;
        },
        shouldContinue: () async =>
            removed ? IngestReport.cardRemovedReason : null,
      );

      expect(report.imported, 3);
      expect(report.failed, 0);
      expect(report.stoppedOnCardRemoval, isTrue);
      expect(downscaler.calls, 3,
          reason: 'the other 37 are never attempted');
    });

    test('a genuinely undecodable photo still lands FAILED', () async {
      await writePhoto('DCIM/A.JPG');
      await writePhoto('DCIM/B.JPG', fill: 4);
      worker = IngestWorker(
        ledger: ledger,
        mediaStore: mediaStore,
        downscaler: FakeDownscaler(failOn: {'B.JPG'}),
        nowMs: () => 1,
      );

      final scan = await worker.scan(source(), scanFolders: const ['DCIM']);
      final report = await worker.import(source(), scan.newCandidates,
          settings: settingsWith());

      expect(report.failed, 1);
      expect(report.stoppedEarly, isFalse,
          reason: 'one bad photo is not a reason to stop the card');
      final failed = await ledger.listByStage(MediaStage.failed);
      expect(failed.single.originalFilename, 'B.JPG');
    });

    test('an empty candidate list is a no-op', () async {
      final report = await worker.import(
        source(),
        const [],
        settings: settingsWith(),
      );
      expect(report.processed, 0);
      expect(report.stoppedEarly, isFalse);
    });
  });

  group('EventMediaStore', () {
    test('rendition paths are deterministic per item and kind', () {
      final a = EventMediaStore.relativePathFor(
        mediaId: 'm1',
        kind: RenditionKind.source,
        eventId: 'EVT1',
      );
      final b = EventMediaStore.relativePathFor(
        mediaId: 'm1',
        kind: RenditionKind.source,
        eventId: 'EVT1',
      );
      expect(a, b, reason: 'a retry overwrites rather than leaking a new file');
      expect(a, 'EVT1/m1-source.jpg');
    });

    test('unscoped when no event is bound', () {
      expect(
        EventMediaStore.relativePathFor(mediaId: 'm1', kind: 'ai'),
        'unscoped/m1-ai.jpg',
      );
    });

    test('ids cannot escape the store', () {
      final path = EventMediaStore.relativePathFor(
        mediaId: '../../etc/passwd',
        kind: 'source',
        eventId: '../evil',
      );
      expect(path.split('/'), hasLength(2));
      for (final segment in path.split('/')) {
        expect(segment, isNot('.'));
        expect(segment, isNot('..'));
        expect(segment.startsWith('.'), isFalse);
      }
    });

    test('a bare dot-dot id degrades to a safe segment', () {
      // Without stripping leading dots this resolves above the store root.
      final path = EventMediaStore.relativePathFor(
        mediaId: 'm1',
        kind: 'source',
        eventId: '..',
      );
      expect(path, 'x/m1-source.jpg');
    });

    test('writes stay inside the store root', () async {
      final path = EventMediaStore.relativePathFor(
        mediaId: 'm1',
        kind: 'source',
        eventId: '..',
      );
      final file = await mediaStore.putBytes(path, [1, 2, 3]);
      expect(file, isNotNull);
      expect(file!.absolute.path, startsWith(mediaDir.absolute.path));
    });

    test('purgeEvent removes an event and reports the file count', () async {
      await mediaStore.putBytes('EVT1/a.jpg', [1, 2, 3]);
      await mediaStore.putBytes('EVT1/b.jpg', [4, 5, 6]);
      await mediaStore.putBytes('EVT2/c.jpg', [7]);

      expect(await mediaStore.bytesForEvent('EVT1'), 6);
      expect(await mediaStore.purgeEvent('EVT1'), 2);
      expect(await mediaStore.getFile('EVT1/a.jpg'), isNull);
      expect(await mediaStore.getFile('EVT2/c.jpg'), isNotNull);
    });

    test('purging an unknown event is harmless', () async {
      expect(await mediaStore.purgeEvent('NOPE'), 0);
    });
  });

  group('DownscaleTarget', () {
    test('a factor of 1.0 lands on the DNP native width', () {
      expect(DownscaleTarget.shortSideFor(1.0), 1920);
    });

    test('scales with the factor', () {
      expect(DownscaleTarget.shortSideFor(0.5), 960);
      expect(DownscaleTarget.shortSideFor(1.5), 2880);
    });

    test('clamps to a sane range', () {
      expect(DownscaleTarget.shortSideFor(0.01), 320);
      expect(DownscaleTarget.shortSideFor(10.0), 4096);
    });
  });
}
