import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_info_model.dart';
import 'package:photobooth/models/event_pipeline/event_pipeline_flags.dart';
import 'package:photobooth/models/event_pipeline/media_item.dart';
import 'package:photobooth/models/event_pipeline/media_rendition.dart';
import 'package:photobooth/screens/event_pipeline/event_capture_viewmodel.dart';
import 'package:photobooth/services/event_manager.dart';
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

  group('shutter', () {
    test('a shot lands in review without writing anything', () async {
      source.next = await frameOnDisk();
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      await vm.shoot();

      expect(vm.phase, CapturePhase.reviewing);
      expect(vm.pendingShot, isNotNull);
      final ledger = EventPipelineLedger(db: db);
      expect(await ledger.stageCounts(eventId: 'EVT1'), isEmpty,
          reason: 'nothing is committed until Confirm');
      expect(downscaler.calls, 0);
    });

    test('a camera that returns nothing says so and stays usable', () async {
      source.next = null;
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      await vm.shoot();

      expect(vm.phase, CapturePhase.ready);
      expect(vm.errorMessage, contains('did not return a photo'));
    });

    test('a camera that throws does not take the screen down', () async {
      source.shouldThrow = true;
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      await vm.shoot();

      expect(vm.phase, CapturePhase.ready);
      expect(vm.errorMessage, isNotNull);
    });

    test('the shutter is ignored while a frame is under review', () async {
      source.next = await frameOnDisk();
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      await vm.shoot();
      await vm.shoot();
      expect(source.shots, 1);
    });
  });

  group('retake', () {
    test('writes nothing at all', () async {
      final shot = await frameOnDisk();
      source.next = shot;
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      await vm.shoot();
      await vm.retake();

      expect(vm.phase, CapturePhase.ready);
      expect(vm.pendingShot, isNull);
      final ledger = EventPipelineLedger(db: db);
      expect(await ledger.knownSourceRefs(MediaSource.ptp), isEmpty);
      expect(await ledger.stageCounts(eventId: 'EVT1'), isEmpty);
      expect(vm.recentShots, isEmpty);
    });

    test('the rejected frame does not stay on disk', () async {
      final shot = await frameOnDisk();
      source.next = shot;
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      await vm.shoot();
      await vm.retake();

      // A rejected retake must not quietly fill the disk: it has no ledger row
      // to find it by later.
      expect(File(shot.originalPath).existsSync(), isFalse);
      expect(File(shot.previewPath!).existsSync(), isFalse);
    });

    test('retaking with nothing pending is harmless', () async {
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);
      await vm.retake();
      expect(vm.phase, CapturePhase.ready);
    });
  });

  group('confirm', () {
    test('registers the frame and queues it into the same queue', () async {
      source.next = await frameOnDisk();
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      await vm.shoot();
      expect(await vm.confirm(), isTrue);

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

      await vm.shoot();
      await vm.confirm();

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

      await vm.shoot();
      await vm.confirm();

      final rows = await db.database.query('evp_media_items');
      expect(rows.single['source'], MediaSource.ptp);
    });

    test('the recent strip shows frames landing', () async {
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      for (var i = 0; i < 2; i++) {
        source.next = await frameOnDisk(fill: 7 + i);
        await vm.shoot();
        await vm.confirm();
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
        await vm.shoot();
        await vm.confirm();
      }
      expect(vm.recentShots, hasLength(3));
    });

    test('the same frame twice is refused rather than duplicated', () async {
      final shot = await frameOnDisk();
      source.next = shot;
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      await vm.shoot();
      await vm.confirm();

      source.next = shot;
      await vm.shoot();
      expect(await vm.confirm(), isFalse);
      expect(vm.errorMessage, contains('already in the queue'));
      expect(vm.phase, CapturePhase.reviewing,
          reason: 'the operator still has to decide what to do with it');
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

      await vm.shoot();
      expect(await vm.confirm(), isFalse);
      expect(vm.errorMessage, contains('not where the camera said'));
      expect(vm.phase, CapturePhase.reviewing);
    });

    test('confirming with nothing pending is harmless', () async {
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);
      expect(await vm.confirm(), isFalse);
    });
  });

  group('resilience', () {
    test('a queue that goes away mid-confirm is reported, not swallowed',
        () async {
      source.next = await frameOnDisk();
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);
      await vm.shoot();

      // The disk going away between the shutter and Confirm. The import path
      // swallows the per-item failure, so nothing is queued and the operator is
      // told rather than the frame silently disappearing.
      await db.close();
      expect(await vm.confirm(), isFalse);
      expect(vm.errorMessage, 'Could not store the photo.');
      expect(vm.phase, CapturePhase.reviewing,
          reason: 'the frame is still on screen to try again with');

      db = (await EventPipelineDb.open(root))!;
    });

    test('a retake whose file has already gone is harmless', () async {
      final shot = await frameOnDisk();
      source.next = shot;
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);
      await vm.shoot();

      await File(shot.originalPath).delete();
      await vm.retake();
      expect(vm.phase, CapturePhase.ready);
    });

    test('a shot with no separate preview is not deleted twice', () async {
      final original = await frameOnDisk();
      source.next = CapturedShot(
        originalPath: original.originalPath,
        previewPath: original.originalPath,
        capturedAtMs: original.capturedAtMs,
      );
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      await vm.shoot();
      await vm.retake();
      expect(File(original.originalPath).existsSync(), isFalse);
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

    test('a camera unplugged mid-review does not discard the frame', () async {
      source.next = await frameOnDisk();
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);
      await vm.shoot();

      source.camera = null;
      await vm.refreshCamera();

      expect(vm.phase, CapturePhase.noCamera);
      expect(vm.pendingShot, isNotNull,
          reason: 'the frame is on disk; the operator still decides');
    });
  });
}
