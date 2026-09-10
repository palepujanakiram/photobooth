import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_info_model.dart';
import 'package:photobooth/models/event_pipeline/event_pipeline_flags.dart';
import 'package:photobooth/models/event_pipeline/media_item.dart';
import 'package:photobooth/models/event_pipeline/media_rendition.dart';
import 'package:photobooth/services/direct_ptp_camera_service.dart';
import 'package:photobooth/services/event_manager.dart';
import 'package:photobooth/services/event_pipeline/capture/event_capture_coordinator.dart';
import 'package:photobooth/services/event_pipeline/event_media_store.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_config.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_db.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_ledger.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_runner.dart';
import 'package:photobooth/services/event_pipeline/ingest/image_downscaler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A camera whose native screen we drive by hand: shots are pushed onto the
/// accepted stream while the session future is still outstanding, exactly as
/// the real one does while its Activity is up.
class FakeCamera extends DirectPtpCameraService {
  final _accepted = StreamController<DirectPtpShot>.broadcast();
  final _sessionDone = Completer<DirectPtpCaptureResult>();
  final messages = <String>[];
  DirectPtpCaptureRequest? lastRequest;
  int listenCalls = 0;

  @override
  Stream<DirectPtpShot> get acceptedShots => _accepted.stream;

  @override
  void listenForAcceptedShots() => listenCalls++;

  @override
  Future<DirectPtpCaptureResult> runCaptureSession(
    DirectPtpCaptureRequest request,
  ) {
    lastRequest = request;
    return _sessionDone.future;
  }

  @override
  Future<void> postCaptureMessage(String text) async => messages.add(text);

  /// The operator accepts a frame; the screen stays up.
  Future<void> accept(DirectPtpShot shot) async {
    _accepted.add(shot);
    // Let the coordinator's listener run to completion.
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  /// The screen fails outright rather than returning a result.
  void failSession(Object error) => _sessionDone.completeError(error);

  /// The operator closes the screen.
  void closeSession() {
    _sessionDone.complete(
      const DirectPtpCaptureResult(status: DirectPtpCaptureStatus.completed),
    );
  }

  Future<void> dispose() => _accepted.close();
}

class FakeDownscaler implements ImageDownscaler {
  @override
  Future<DownscaleResult> downscale({
    required String sourceUri,
    required int targetShortSide,
    int maxLongSide = 4096,
    int quality = 88,
    int thumbShortSide = 0,
  }) async {
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
  late FakeCamera camera;
  var frames = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    EventPipelineConfig.resetCacheForTests();
    EventPipelineRunner.resetInstanceForTests();
    EventManager.resetCacheForTests();
    root = await Directory.systemTemp.createTemp('fz_evp_coord_');
    mediaDir = Directory('${root.path}/media')..createSync(recursive: true);
    cameraDir = Directory('${root.path}/camera')..createSync(recursive: true);
    frames = 0;
    db = (await EventPipelineDb.open(root))!;
    media = EventMediaStore(resolveDirectory: () async => mediaDir);
    camera = FakeCamera();

    await EventManager().cacheVerifyResult(
      const EventInfoModel(
        id: 'EVT1',
        code: 'GALA-01',
        name: 'Priya & Arjun',
        chrome: EventChrome(
          tagline: 'Warm peach to purple',
          skin: EventSkinChrome(ink: '#FFFFFF', bannerFrom: '#E3A65C'),
        ),
      ),
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
    await camera.dispose();
    runner.stop();
    EventPipelineRunner.resetInstanceForTests();
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<DirectPtpShot> frameOnDisk({int fill = 7}) async {
    frames++;
    final file = File('${cameraDir.path}/IMG_$frames.JPG');
    final bytes = Uint8List(4096);
    bytes[0] = 0xFF;
    bytes[1] = 0xD8;
    for (var i = 2; i < bytes.length; i++) {
      bytes[i] = fill;
    }
    await file.writeAsBytes(bytes);
    return DirectPtpShot(
      originalPath: file.path,
      capturedAtMs: 1700000000000 + frames,
      widthPx: 6000,
      heightPx: 4000,
      bytes: bytes.length,
    );
  }

  EventCaptureCoordinator build() => EventCaptureCoordinator(
        camera: camera,
        runner: runner,
        events: EventManager(),
        mediaStore: media,
        downscaler: FakeDownscaler(),
      );

  test('each accepted frame is queued while the screen is still up', () async {
    final coordinator = build();
    final session = coordinator.runSession();

    // Three shots, all accepted, with the screen never closing between them.
    await camera.accept(await frameOnDisk(fill: 1));
    await camera.accept(await frameOnDisk(fill: 2));
    final ledger = EventPipelineLedger(db: db);
    expect(
      await ledger.countItems(eventId: 'EVT1'),
      2,
      reason: 'queued as they land, not when the operator leaves',
    );

    await camera.accept(await frameOnDisk(fill: 3));
    camera.closeSession();
    expect(await session, 3);
  });

  test('a captured frame is recorded as a camera photo', () async {
    final coordinator = build();
    final session = coordinator.runSession();
    await camera.accept(await frameOnDisk());
    camera.closeSession();
    await session;

    final rows = await db.database.query('evp_media_items');
    expect(rows.single['source'], MediaSource.ptp);
  });

  test('it runs the same import path a card does', () async {
    final coordinator = build();
    final session = coordinator.runSession();
    await camera.accept(await frameOnDisk());
    camera.closeSession();
    await session;

    // Identical dedupe, downscale, thumbnail and ledger handling — not a
    // second implementation free to drift.
    final ledger = EventPipelineLedger(db: db);
    final id = coordinator.queuedIds.single;
    final kinds = [for (final r in await ledger.renditionsFor(id)) r.kind];
    expect(kinds, containsAll([RenditionKind.source, RenditionKind.thumb]));
    final item = await ledger.findById(id);
    expect(item!.isSelected, isTrue, reason: 'queued with its chain frozen');
  });

  test('the session is continuous and wears the event chrome', () async {
    final coordinator = build();
    final session = coordinator.runSession();
    camera.closeSession();
    await session;

    final args = camera.lastRequest!.toArguments();
    expect(args['continuous'], isTrue);
    expect(args['titleText'], 'Priya & Arjun');
    expect(args['inkColor'], '#FFFFFF');
    expect(args['accentColor'], '#E3A65C');
    expect(args['countdownSeconds'], 0);
  });

  test('nothing is said when a frame queues cleanly', () async {
    final coordinator = build();
    final session = coordinator.runSession();
    await camera.accept(await frameOnDisk());
    camera.closeSession();
    await session;

    // The screen already said "Added to queue" when it handed the frame over.
    expect(camera.messages, isEmpty);
  });

  test('a duplicate frame is corrected on the screen', () async {
    final coordinator = build();
    final session = coordinator.runSession();
    final shot = await frameOnDisk();
    await camera.accept(shot);
    await camera.accept(shot);
    camera.closeSession();
    await session;

    // An operator must never be told a photo landed when it did not.
    expect(camera.messages, contains('Already in the queue'));
    expect(coordinator.queuedIds, hasLength(1));
  });

  test('a frame the camera stack lost is reported', () async {
    final coordinator = build();
    final session = coordinator.runSession();
    await camera.accept(const DirectPtpShot(
      originalPath: '/nowhere/IMG_9999.JPG',
      capturedAtMs: 1,
    ));
    camera.closeSession();
    await session;

    expect(camera.messages, contains('The photo was not where the camera said'));
  });

  test('a session with nothing accepted queues nothing', () async {
    final coordinator = build();
    final session = coordinator.runSession();
    camera.closeSession();

    expect(await session, 0);
    expect(camera.listenCalls, 1);
  });

  test('a coordinator built before anything started still queues', () async {
    // The hub view model builds this inside its own initializer list, before
    // any runner exists — so `EventPipelineRunner.instance` is null at that
    // moment. Capturing it there bound the coordinator to a second, unstarted
    // runner whose ledger never appeared, and every accepted frame reported
    // "Storage unavailable" while the hub's counters worked perfectly.
    EventPipelineRunner.resetInstanceForTests();
    expect(EventPipelineRunner.instance, isNull);

    final coordinator = EventCaptureCoordinator(
      camera: camera,
      // Exactly what the hub passes when nothing has started yet.
      runner: EventPipelineRunner.instance,
      events: EventManager(),
      mediaStore: media,
      downscaler: FakeDownscaler(),
    );

    // The pipeline starts afterwards, as it does on a real cold boot.
    await runner.ensureStarted();
    expect(EventPipelineRunner.instance, isNotNull);

    final session = coordinator.runSession();
    await camera.accept(await frameOnDisk());
    camera.closeSession();

    expect(await session, 1);
    expect(camera.messages, isEmpty, reason: 'nothing went wrong to report');
    expect(await EventPipelineLedger(db: db).countItems(eventId: 'EVT1'), 1);
  });

  test('a shot with no capture time is stamped on arrival', () async {
    final coordinator = build();
    final session = coordinator.runSession();
    final shot = await frameOnDisk();
    final before = DateTime.now().millisecondsSinceEpoch;
    // Some stacks return 0 rather than a time; the frame still has to be
    // orderable in the queue.
    await camera.accept(DirectPtpShot(
      originalPath: shot.originalPath,
      capturedAtMs: 0,
      widthPx: shot.widthPx,
      heightPx: shot.heightPx,
      bytes: shot.bytes,
    ));
    camera.closeSession();
    await session;

    final item = await EventPipelineLedger(db: db)
        .findById(coordinator.queuedIds.single);
    expect(item!.capturedAtMs, greaterThanOrEqualTo(before));
  });

  test('a capture session that throws leaves the operator on the hub',
      () async {
    final coordinator = build();
    final session = coordinator.runSession();
    // Let runSession reach its await, or the error has no listener yet and the
    // zone reports it as unhandled before the try/catch can see it.
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    camera.failSession(StateError('activity died'));

    // Never rethrown: a failed session is a message, not a crash.
    expect(await session, 0);
  });

  test('storage going away mid-session is reported on the screen', () async {
    final coordinator = build();
    final session = coordinator.runSession();
    final shot = await frameOnDisk();
    await db.close();
    await camera.accept(shot);
    camera.closeSession();
    await session;

    // The import path swallows the per-item failure and returns no ids, so the
    // operator is told the photo did not store rather than that it queued.
    expect(camera.messages, contains('Could not store the photo'));
    expect(coordinator.queuedIds, isEmpty);
    db = (await EventPipelineDb.open(root))!;
  });

  test('it reports the attached camera by name', () async {
    expect(await build().cameraName(), isNull,
        reason: 'the fake probes nothing, so there is no camera to name');
  });
}
