import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_info_model.dart';
import 'package:photobooth/models/event_pipeline/event_pipeline_flags.dart';
import 'package:photobooth/models/event_pipeline/media_item.dart';
import 'package:photobooth/models/event_pipeline/media_rendition.dart';
import 'package:photobooth/screens/event_pipeline/event_capture_viewmodel.dart';
import 'package:photobooth/services/event_manager.dart';
import 'package:photobooth/services/event_pipeline/capture/direct_ptp_capture_source.dart';
import 'package:photobooth/services/event_pipeline/capture/event_capture_source.dart';
import 'package:photobooth/services/event_pipeline/event_media_store.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_config.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_db.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_ledger.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_queue.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_runner.dart';
import 'package:photobooth/services/event_pipeline/ingest/image_downscaler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manual fakes by subclass-and-override, per the repo convention.
class FakeCaptureSource implements EventCaptureSource {
  FakeCaptureSource({this.camera = 'Canon EOS R'});

  String? camera;
  CapturedShot? next;
  bool shouldThrow = false;
  int shots = 0;
  bool disposed = false;

  @override
  Future<String?> cameraName() async => camera;

  @override
  Future<CapturedShot?> shoot() async {
    shots++;
    if (shouldThrow) throw StateError('usb gone');
    return next;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class FakeDownscaler implements ImageDownscaler {
  int calls = 0;

  @override
  Future<DownscaleResult> downscale({
    required String sourceUri,
    required int targetShortSide,
    int maxLongSide = 4096,
    int quality = 88,
    int thumbShortSide = 0,
  }) async {
    calls++;
    return DownscaleResult(
      bytes: Uint8List.fromList(List<int>.filled(512, 4)),
      width: targetShortSide,
      height: targetShortSide,
      thumbBytes: thumbShortSide <= 0
          ? null
          : Uint8List.fromList(List<int>.filled(64, 8)),
      thumbWidth: thumbShortSide,
      thumbHeight: thumbShortSide,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory mediaDir;
  late Directory cameraDir;
  late EventPipelineDb db;
  late EventMediaStore media;
  late EventPipelineRunner runner;
  late FakeCaptureSource source;
  late FakeDownscaler downscaler;
  var frames = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    EventPipelineConfig.resetCacheForTests();
    EventPipelineRunner.resetInstanceForTests();
    EventManager.resetCacheForTests();
    root = await Directory.systemTemp.createTemp('fz_evp_capture_');
    mediaDir = Directory('${root.path}/media')..createSync(recursive: true);
    cameraDir = Directory('${root.path}/camera')..createSync(recursive: true);
    frames = 0;
    db = (await EventPipelineDb.open(root))!;
    media = EventMediaStore(resolveDirectory: () async => mediaDir);
    source = FakeCaptureSource();
    downscaler = FakeDownscaler();
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

  /// Writes a frame where the camera stack would have left it.
  Future<CapturedShot> frameOnDisk({int fill = 7}) async {
    frames++;
    final file = File('${cameraDir.path}/IMG_$frames.JPG');
    final bytes = Uint8List(4096);
    bytes[0] = 0xFF;
    bytes[1] = 0xD8;
    for (var i = 2; i < bytes.length; i++) {
      bytes[i] = fill;
    }
    await file.writeAsBytes(bytes);
    final preview = File('${cameraDir.path}/IMG_$frames-display.JPG');
    await preview.writeAsBytes(Uint8List.fromList(List<int>.filled(128, 2)));
    return CapturedShot(
      originalPath: file.path,
      previewPath: preview.path,
      capturedAtMs: 1700000000000 + frames,
      width: 6000,
      height: 4000,
      bytes: bytes.length,
    );
  }

  EventCaptureViewModel build() => EventCaptureViewModel(
        source: source,
        runner: runner,
        mediaStore: media,
        downscaler: downscaler,
        recentLimit: 3,
      );

  group('camera', () {
    test('no camera on the bus is its own state', () async {
      source.camera = null;
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.phase, CapturePhase.noCamera);
      expect(vm.canShoot, isFalse);
    });

    test('a connected camera is named and ready', () async {
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.cameraName, 'Canon EOS R');
      expect(vm.phase, CapturePhase.ready);
      expect(vm.canShoot, isTrue);
    });

    test('the camera is released when the screen closes', () async {
      final vm = build();
      await vm.start();
      vm.dispose();
      expect(source.disposed, isTrue);
    });
  });

  group('viewfinder', () {
    test('an accepted frame is committed without a second review', () async {
      source.next = await frameOnDisk();
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      // The native review already asked; anything that comes back was
      // accepted, so asking again in Dart was the double-confirm this removed.
      expect(await vm.openViewfinder(), isTrue);
      expect(vm.phase, CapturePhase.ready);
      expect(vm.recentShots, hasLength(1));
    });

    test('a retake never reaches Dart at all', () async {
      // The native review discards it and loops back to live view, so nothing
      // comes back and nothing is written.
      source.next = null;
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      expect(await vm.openViewfinder(), isFalse);
      expect(vm.phase, CapturePhase.ready);
      final ledger = EventPipelineLedger(db: db);
      expect(await ledger.stageCounts(eventId: 'EVT1'), isEmpty);
      expect(downscaler.calls, 0);
    });

    test('closing the viewfinder is not an error', () async {
      source.next = null;
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      await vm.openViewfinder();
      expect(vm.errorMessage, isNull,
          reason: 'the operator closed it; nothing went wrong');
    });

    test('a camera that throws does not take the screen down', () async {
      source.shouldThrow = true;
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      await vm.openViewfinder();

      expect(vm.phase, CapturePhase.ready);
      expect(vm.errorMessage, isNotNull);
    });

    test('the viewfinder can be reopened for the next shot', () async {
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      for (var i = 0; i < 3; i++) {
        source.next = await frameOnDisk(fill: 20 + i);
        expect(await vm.openViewfinder(), isTrue);
      }
      expect(source.shots, 3);
      expect(vm.recentShots, hasLength(3));
    });
  });

  group('committing', () {
    test('registers the frame and queues it into the same queue', () async {
      source.next = await frameOnDisk();
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      expect(await vm.openViewfinder(), isTrue);

      final ledger = EventPipelineLedger(db: db);
      final counts = await ledger.stageCounts(eventId: 'EVT1');
      expect(counts.values.fold<int>(0, (a, b) => a + b), 1);

      // Queued with the chain frozen at this moment, exactly like an import.
      final queued = await ledger.listPage(limit: 10, eventId: 'EVT1');
      expect(queued, hasLength(1));
      expect(queued.single.steps, ['print']);
      expect(queued.single.isSelected, isTrue);
      final queue = EventPipelineQueue(db: db);
      expect(
        await queue.findFor(kind: 'print', mediaId: queued.single.id),
        isNotNull,
      );
    });

    test('a captured frame gets the same derivatives an import does', () async {
      source.next = await frameOnDisk();
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      await vm.openViewfinder();

      final ledger = EventPipelineLedger(db: db);
      final id = vm.recentShots.single.mediaId;
      final kinds = [for (final r in await ledger.renditionsFor(id)) r.kind];
      expect(kinds, containsAll([RenditionKind.source, RenditionKind.thumb]));
    });

    test('it is recorded as a camera frame, not a card import', () async {
      source.next = await frameOnDisk();
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      await vm.openViewfinder();

      final rows = await db.database.query('evp_media_items');
      expect(rows.single['source'], MediaSource.ptp);
    });

    test('the recent strip shows frames landing', () async {
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      for (var i = 0; i < 2; i++) {
        source.next = await frameOnDisk(fill: 7 + i);
        await vm.openViewfinder();
      }

      // A photographer needs to see frames landing to trust it is working.
      expect(vm.recentShots, hasLength(2));
      expect(vm.recentShots.first.thumbnail, isNotNull);
    });

    test('the recent strip is bounded', () async {
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      for (var i = 0; i < 5; i++) {
        source.next = await frameOnDisk(fill: 10 + i);
        await vm.openViewfinder();
      }
      expect(vm.recentShots, hasLength(3));
    });

    test('the same frame twice is refused rather than duplicated', () async {
      final shot = await frameOnDisk();
      source.next = shot;
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      await vm.openViewfinder();

      source.next = shot;
      expect(await vm.openViewfinder(), isFalse);
      expect(vm.errorMessage, contains('already in the queue'));
      expect(vm.phase, CapturePhase.ready);
    });

    test('a frame the camera stack lost is reported, not silently dropped',
        () async {
      source.next = const CapturedShot(
        originalPath: '/nowhere/IMG_9999.JPG',
        capturedAtMs: 1,
      );
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      expect(await vm.openViewfinder(), isFalse);
      expect(vm.errorMessage, contains('not where the camera said'));
      expect(vm.phase, CapturePhase.ready);
    });

    test('opening the viewfinder with no camera does nothing', () async {
      source.camera = null;
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);
      expect(await vm.openViewfinder(), isFalse);
      expect(source.shots, 0);
    });
  });

  group('resilience', () {
    test('a queue that goes away is reported, not swallowed', () async {
      source.next = await frameOnDisk();
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      // The disk going away while the operator was in the viewfinder. The
      // import path swallows the per-item failure, so nothing is queued and the
      // operator is told rather than the frame silently disappearing.
      await db.close();
      expect(await vm.openViewfinder(), isFalse);
      expect(vm.errorMessage, 'Could not store the photo.');
      expect(vm.phase, CapturePhase.ready);

      db = (await EventPipelineDb.open(root))!;
    });

    test('reconnecting a camera returns the screen to ready', () async {
      source.camera = null;
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);
      expect(vm.phase, CapturePhase.noCamera);

      source.camera = 'Canon EOS R';
      await vm.refreshCamera();
      expect(vm.phase, CapturePhase.ready);
    });
  });

  group('event chrome', () {
    test('the viewfinder wears the event name and colours', () async {
      // A photographer looks at this screen all evening; it should belong to
      // the event rather than read as a generic booth.
      final request = DirectPtpCaptureSource.requestFor(
        title: 'Priya & Arjun',
        subtitle: 'Warm peach to purple',
        ink: '#FFFFFF',
        accent: '#E3A65C',
        background: '#6E5391',
      );
      final args = request.toArguments();

      expect(args['titleText'], 'Priya & Arjun');
      expect(args['subtitleText'], 'Warm peach to purple');
      expect(args['inkColor'], '#FFFFFF');
      expect(args['accentColor'], '#E3A65C');
      expect(args['backgroundColor'], '#6E5391');
    });

    test('the operator session has no countdown and no guest uploads', () {
      final args = DirectPtpCaptureSource.requestFor().toArguments();
      expect(args['countdownSeconds'], 0);
      expect(args['autoStart'], isFalse);
      expect(args['allowGalleryUpload'], isFalse);
      expect(args['allowPhoneUpload'], isFalse);
      expect(args['showCountdownHeadline'], isFalse);
      // 0 holds the shot indefinitely with Retake and Accept — the confirm
      // step, which is why Dart no longer has one.
      expect(args['reviewHoldMs'], 0);
    });
  });
}
