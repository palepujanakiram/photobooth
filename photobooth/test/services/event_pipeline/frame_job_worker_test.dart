import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_pipeline/event_frame.dart';
import 'package:photobooth/models/event_pipeline/event_pipeline_settings.dart';
import 'package:photobooth/models/event_pipeline/event_print_size.dart';
import 'package:photobooth/models/event_pipeline/media_item.dart';
import 'package:photobooth/models/event_pipeline/media_rendition.dart';
import 'package:photobooth/models/event_pipeline/pipeline_job.dart';
import 'package:photobooth/models/kiosk_frame_model.dart';
import 'package:photobooth/services/api_service.dart';
import 'package:photobooth/services/event_pipeline/event_frame_cache.dart';
import 'package:photobooth/services/event_pipeline/event_media_store.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_db.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_ledger.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_queue.dart';
import 'package:photobooth/services/event_pipeline/frame_compositor.dart';
import 'package:photobooth/services/event_pipeline/frame_job_worker.dart';

/// Manual fakes by subclass-and-override, per the repo convention.
class FakeApiService extends ApiService {
  FakeApiService({this.frames = const [], this.throwOnFetch = false});

  List<KioskFrameModel> frames;
  bool throwOnFetch;
  int fetchCalls = 0;

  @override
  Future<List<KioskFrameModel>> getKioskFrames() async {
    fetchCalls++;
    if (throwOnFetch) throw Exception('no network');
    return frames;
  }
}

class FakeCompositor implements FrameCompositor {
  FakeCompositor({this.shouldThrow = false});

  bool shouldThrow;
  int calls = 0;
  String? lastPhotoPath;
  String? lastFramePath;
  EventPrintSize? lastSize;

  @override
  Future<CompositeResult> composite({
    required String photoPath,
    required String? framePath,
    required EventPrintSize size,
    int quality = 88,
  }) async {
    calls++;
    lastPhotoPath = photoPath;
    lastFramePath = framePath;
    lastSize = size;
    if (shouldThrow) throw StateError('decode failed');
    return CompositeResult(
      bytes: Uint8List.fromList(List<int>.filled(1024, 5)),
      width: size.width,
      height: size.height,
    );
  }
}

EventPipelineSettings settingsWith({
  String? frameId = 'frame-1',
  String printSize = 's4x6',
}) {
  return EventPipelineSettings(
    pipelineEnabled: true,
    offlineMode: true,
    aiEnabled: false,
    frameEnabled: true,
    frameId: frameId,
    autoPrint: true,
    defaultCopies: 1,
    printSize: printSize,
    qualityFactor: 1.0,
    mirrorEnabled: false,
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
  late FakeApiService api;
  late FakeCompositor compositor;
  var ids = 0;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fz_evp_frame_');
    mediaDir = Directory('${root.path}/media')..createSync(recursive: true);
    ids = 0;
    db = (await EventPipelineDb.open(root))!;
    ledger = EventPipelineLedger(db: db, newId: () => 'm${ids++}');
    queue = EventPipelineQueue(db: db, newId: () => 'j${ids++}');
    mediaStore = EventMediaStore(resolveDirectory: () async => mediaDir);
    api = FakeApiService();
    compositor = FakeCompositor();
  });

  tearDown(() async {
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  EventFrameCache buildCache({
    Future<List<int>> Function(String)? fetchBytes,
  }) {
    return EventFrameCache(
      db: db,
      mediaStore: mediaStore,
      api: api,
      fetchBytes: fetchBytes ??
          (_) async => Uint8List.fromList(List<int>.filled(256, 9)),
      nowMs: () => 42,
    );
  }

  Future<String> seedItemWithSource() async {
    final result = await ledger.insertIfNew(
      source: MediaSource.sdCard,
      sourceRef: 'VOL:DCIM/A.JPG:100:200',
      contentKey: 'ck-1',
      eventId: 'EVT1',
    );
    await mediaStore.putBytes('EVT1/${result.item.id}-source.jpg', [1, 2, 3]);
    await ledger.putRendition(MediaRendition(
      mediaId: result.item.id,
      kind: RenditionKind.source,
      path: 'EVT1/${result.item.id}-source.jpg',
      createdAtMs: 1,
    ));
    return result.item.id;
  }

  group('EventFrameCache', () {
    test('downloads overlays and reports frames ready', () async {
      api.frames = const [
        KioskFrameModel(id: 'frame-1', name: 'Priya', overlayUrl: '/f1.png'),
      ];
      final cache = buildCache();
      final status = await cache.refresh(
        eventId: 'EVT1',
        selectedFrameId: 'frame-1',
      );

      expect(status.total, 1);
      expect(status.cached, 1);
      expect(status.allCached, isTrue);
      expect(status.selectedIsCached, isTrue);
      expect(status.summary, 'Frames ready — 1 cached');
      expect(await cache.localFilePath('frame-1'), isNotNull);
    });

    test('a failed download leaves the frame uncached, not half-recorded',
        () async {
      api.frames = const [
        KioskFrameModel(id: 'frame-1', name: 'F', overlayUrl: '/f1.png'),
      ];
      final cache = buildCache(fetchBytes: (_) async => <int>[]);
      final status = await cache.refresh(
        eventId: 'EVT1',
        selectedFrameId: 'frame-1',
      );

      expect(status.total, 1);
      expect(status.cached, 0);
      expect(status.selectedIsCached, isFalse);
      expect(await cache.localFilePath('frame-1'), isNull);
    });

    test('a catalogue fetch failure falls back to what is already cached',
        () async {
      api.frames = const [
        KioskFrameModel(id: 'frame-1', name: 'F', overlayUrl: '/f1.png'),
      ];
      final cache = buildCache();
      await cache.refresh(eventId: 'EVT1', selectedFrameId: 'frame-1');

      // The link drops before the next refresh.
      api.throwOnFetch = true;
      final status = await cache.refresh(
        eventId: 'EVT1',
        selectedFrameId: 'frame-1',
      );
      expect(status.cached, 1, reason: 'the cached overlay still counts');
      expect(status.selectedIsCached, isTrue);
    });

    test('a second refresh does not re-download an unchanged overlay',
        () async {
      api.frames = const [
        KioskFrameModel(id: 'frame-1', name: 'F', overlayUrl: '/f1.png'),
      ];
      var fetches = 0;
      final cache = buildCache(fetchBytes: (_) async {
        fetches++;
        return Uint8List.fromList(List<int>.filled(256, 9));
      });
      await cache.refresh(eventId: 'EVT1');
      await cache.refresh(eventId: 'EVT1');
      expect(fetches, 1);
    });

    test('a changed overlay URL invalidates the cached copy', () async {
      api.frames = const [
        KioskFrameModel(id: 'frame-1', name: 'F', overlayUrl: '/f1.png'),
      ];
      var fetches = 0;
      final cache = buildCache(fetchBytes: (_) async {
        fetches++;
        return Uint8List.fromList(List<int>.filled(256, 9));
      });
      await cache.refresh(eventId: 'EVT1');

      api.frames = const [
        KioskFrameModel(id: 'frame-1', name: 'F', overlayUrl: '/f1-v2.png'),
      ];
      await cache.refresh(eventId: 'EVT1');
      expect(fetches, 2, reason: 'the artwork changed, so re-fetch it');
    });

    test('no frames reports empty rather than ready', () async {
      final status = await buildCache().status(eventId: 'EVT1');
      expect(status.isEmpty, isTrue);
      expect(status.allCached, isFalse);
      expect(status.summary, 'No frames for this event');
    });

    test('a partial download reports incomplete', () async {
      api.frames = const [
        KioskFrameModel(id: 'f1', name: 'A', overlayUrl: '/a.png'),
        KioskFrameModel(id: 'f2', name: 'B', overlayUrl: '/b.png'),
      ];
      final cache = buildCache(
        fetchBytes: (url) async => url.contains('/a.png')
            ? Uint8List.fromList(List<int>.filled(16, 1))
            : <int>[],
      );
      final status = await cache.refresh(eventId: 'EVT1');
      expect(status.summary, 'Frames incomplete — 1 of 2 downloaded');
    });
  });

  group('FrameJobWorker', () {
    FrameJobWorker buildWorker({
      EventFrameCache? cache,
      EventPipelineSettings? settings,
    }) {
      return FrameJobWorker(
        queue: queue,
        ledger: ledger,
        frameCache: cache ?? buildCache(),
        mediaStore: mediaStore,
        compositor: compositor,
        settings: () => settings ?? settingsWith(),
        nowMs: () => 7,
      );
    }

    test('composites onto the print raster and stores a framed rendition',
        () async {
      api.frames = const [
        KioskFrameModel(id: 'frame-1', name: 'F', overlayUrl: '/f1.png'),
      ];
      final cache = buildCache();
      await cache.refresh(eventId: 'EVT1');

      final mediaId = await seedItemWithSource();
      await ledger.markSelected(mediaId, const ['frame', 'print']);
      await queue.enqueue(kind: 'frame', mediaId: mediaId, eventId: 'EVT1');

      expect(await buildWorker(cache: cache).drain(), 1);

      expect(compositor.calls, 1);
      expect(compositor.lastSize!.token, 's4x6');
      expect(compositor.lastFramePath, isNotNull);

      final framed = await ledger.bestRenditionForPrint(mediaId);
      expect(framed!.kind, RenditionKind.framed);
      expect(framed.width, EventPrintSize.size4x6.width);
      expect(await mediaStore.getFile(framed.path), isNotNull);
    });

    test('advances to print and enqueues the next job', () async {
      api.frames = const [
        KioskFrameModel(id: 'frame-1', name: 'F', overlayUrl: '/f1.png'),
      ];
      final cache = buildCache();
      await cache.refresh(eventId: 'EVT1');

      final mediaId = await seedItemWithSource();
      await ledger.markSelected(mediaId, const ['frame', 'print']);
      await queue.enqueue(kind: 'frame', mediaId: mediaId, eventId: 'EVT1');
      await buildWorker(cache: cache).drain();

      final item = await ledger.findById(mediaId);
      expect(item!.currentStep, 'print');
      expect(item.stage, MediaStage.printing);
      expect(await queue.findFor(kind: 'print', mediaId: mediaId), isNotNull);
    });

    test('an uncached frame defers without consuming an attempt', () async {
      final mediaId = await seedItemWithSource();
      await ledger.markSelected(mediaId, const ['frame', 'print']);
      final job =
          await queue.enqueue(kind: 'frame', mediaId: mediaId, eventId: 'EVT1');

      // No refresh has run, so the overlay is not on disk.
      expect(await buildWorker().drain(), 0);

      final reloaded = await queue.findById(job.id);
      expect(reloaded!.status, PipelineJobStatus.pending);
      expect(reloaded.attempts, 0, reason: 'waiting for a download is not failing');
      expect(compositor.calls, 0);
    });

    test('no configured frame fails permanently rather than retrying', () async {
      final mediaId = await seedItemWithSource();
      await ledger.markSelected(mediaId, const ['frame', 'print']);
      final job =
          await queue.enqueue(kind: 'frame', mediaId: mediaId, eventId: 'EVT1');

      await buildWorker(settings: settingsWith(frameId: null)).drain();

      final reloaded = await queue.findById(job.id);
      expect(reloaded!.status, PipelineJobStatus.failed);
    });

    test('an item with no stored image fails rather than compositing nothing',
        () async {
      final result = await ledger.insertIfNew(
        source: MediaSource.sdCard,
        sourceRef: 'VOL:DCIM/B.JPG:1:2',
        contentKey: 'ck-2',
        eventId: 'EVT1',
      );
      await queue.enqueue(kind: 'frame', mediaId: result.item.id);
      await buildWorker().drain();
      expect((await queue.counts('frame')).failed, 1);
    });

    test('a composite failure retries and leaves print able to fall back',
        () async {
      api.frames = const [
        KioskFrameModel(id: 'frame-1', name: 'F', overlayUrl: '/f1.png'),
      ];
      final cache = buildCache();
      await cache.refresh(eventId: 'EVT1');
      compositor.shouldThrow = true;

      final mediaId = await seedItemWithSource();
      await ledger.markSelected(mediaId, const ['frame', 'print']);
      await queue.enqueue(kind: 'frame', mediaId: mediaId, eventId: 'EVT1');
      await buildWorker(cache: cache).drain();

      expect((await queue.counts('frame')).pending, 1);
      // The source derivative is still printable.
      final best = await ledger.bestRenditionForPrint(mediaId);
      expect(best!.kind, RenditionKind.source);
    });

    test('the print size drives the canvas', () async {
      api.frames = const [
        KioskFrameModel(id: 'frame-1', name: 'F', overlayUrl: '/f1.png'),
      ];
      final cache = buildCache();
      await cache.refresh(eventId: 'EVT1');

      final mediaId = await seedItemWithSource();
      await ledger.markSelected(mediaId, const ['frame']);
      await queue.enqueue(kind: 'frame', mediaId: mediaId, eventId: 'EVT1');
      await buildWorker(
        cache: cache,
        settings: settingsWith(printSize: 's6x8'),
      ).drain();

      expect(compositor.lastSize!.height, 2436);
    });
  });

  group('EventPrintSize', () {
    test('resolves both token spellings', () {
      expect(EventPrintSize.fromToken('s4x6').label, '4x6');
      expect(EventPrintSize.fromToken('s6x4').label, '4x6');
      expect(EventPrintSize.fromToken('s6x2_2').label, '2x6');
    });

    test('defaults to 4x6 for anything unrecognised', () {
      expect(EventPrintSize.fromToken(null).label, '4x6');
      expect(EventPrintSize.fromToken('nonsense').label, '4x6');
    });

    test('every size shares the DNP native width', () {
      for (final size in EventPrintSize.all) {
        expect(size.width, EventPrintSize.nativeWidth);
      }
    });
  });

  group('EventFrame', () {
    test('is cached only once a local path is recorded', () {
      const frame = EventFrame(
        id: 'f',
        eventId: 'e',
        overlayUrl: '/f.png',
      );
      expect(frame.isCached, isFalse);
      expect(frame.copyWith(localPath: 'e/f.png').isCached, isTrue);
    });
  });
}
