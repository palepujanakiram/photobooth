import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photobooth/models/event_pipeline/event_pipeline_flags.dart';
import 'package:photobooth/models/event_pipeline/media_item.dart';
import 'package:photobooth/screens/event_pipeline/event_ingest_viewmodel.dart';
import 'package:photobooth/services/event_pipeline/event_media_store.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_config.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_db.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_runner.dart';
import 'package:photobooth/services/event_pipeline/ingest/card_detect_channel.dart';
import 'package:photobooth/services/event_pipeline/ingest/event_storage_channel.dart';
import 'package:photobooth/services/event_pipeline/ingest/image_downscaler.dart';
import 'package:photobooth/services/event_pipeline/ingest/media_store_ingest_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manual fakes by subclass-and-override, per the repo convention.
class FakeStorageChannel extends EventStorageChannel {
  FakeStorageChannel({this.volumes = const [], this.rows = const []});

  List<ExternalVolume> volumes;
  List<Map<Object?, Object?>> rows;
  int queryCalls = 0;

  @override
  Future<List<ExternalVolume>> listVolumes() async => volumes;

  @override
  Future<List<Map<Object?, Object?>>> queryImages({
    required String volumeName,
    List<String>? folders,
  }) async {
    queryCalls++;
    return rows;
  }

  @override
  Future<Uint8List> readRange(String uri, int offset, int length) async {
    // Distinct bytes per uri so content keys differ between photos.
    return Uint8List.fromList(List<int>.filled(16, uri.hashCode & 0xFF));
  }
}

class FakeCardDetect extends CardDetectChannel {
  final controller = StreamController<CardEvent>.broadcast();

  @override
  Stream<CardEvent> events() => controller.stream;
}

class FakeDownscaler implements ImageDownscaler {
  int calls = 0;

  /// Runs after each downscale, so a test can pull the card mid-import.
  void Function(int call)? onCall;

  @override
  Future<DownscaleResult> downscale({
    required String sourceUri,
    required int targetShortSide,
    int maxLongSide = 4096,
    int quality = 88,
    int thumbShortSide = 0,
  }) async {
    calls++;
    onCall?.call(calls);
    // Let the card-detect stream deliver between photos, as it would on device.
    await Future<void>.delayed(Duration.zero);
    return DownscaleResult(
      bytes: Uint8List.fromList(List<int>.filled(512, 1)),
      width: targetShortSide,
      height: targetShortSide,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory mediaDir;
  late EventPipelineDb db;
  late FakeStorageChannel storage;
  late FakeCardDetect cardDetect;
  late FakeDownscaler downscaler;
  late EventPipelineConfig config;

  const usableVolume = ExternalVolume(
    uuid: 'VOL-1',
    description: 'SD card',
    isRemovable: true,
    isIndexed: true,
    mediaStoreVolumeName: 'vol-1',
  );

  Map<Object?, Object?> row(String name, {String folder = 'DCIM/100CANON'}) {
    return <Object?, Object?>{
      'uri': 'content://media/vol-1/images/media/$name',
      'displayName': name,
      'relativePath': '$folder/$name',
      'folder': folder,
      'sizeBytes': 6000000,
      'modifiedAtMs': 1700000000000,
      'capturedAtMs': 1699999999000,
      'mimeType': 'image/jpeg',
    };
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    EventPipelineConfig.resetCacheForTests();
    root = await Directory.systemTemp.createTemp('fz_evp_vm_');
    mediaDir = Directory('${root.path}/media')..createSync(recursive: true);
    db = (await EventPipelineDb.open(root))!;
    storage = FakeStorageChannel();
    cardDetect = FakeCardDetect();
    downscaler = FakeDownscaler();
    EventPipelineRunner.resetInstanceForTests();
    config = EventPipelineConfig();
    await config.cacheFlags(
      const EventPipelineFlags(pipelineEnabled: true, autoPrint: true),
    );
  });

  tearDown(() async {
    await cardDetect.controller.close();
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  EventIngestViewModel build({
    PermissionStatus permission = PermissionStatus.granted,
  }) {
    return EventIngestViewModel(
      storage: storage,
      cardDetect: cardDetect,
      config: config,
      mediaStore: EventMediaStore(resolveDirectory: () async => mediaDir),
      downscaler: downscaler,
      settleWatcher: MediaStoreSettleWatcher(
        // Real interval is 2s; the suite would otherwise spend ~24s asleep.
        pollInterval: const Duration(milliseconds: 1),
        stableReadsRequired: 2,
        timeout: const Duration(milliseconds: 200),
      ),
      openDb: () async => db,
      // Injected so the view model does not reach for real storage or platform
      // channels when it starts the workers.
      runner: EventPipelineRunner(
        config: config,
        mediaStore: EventMediaStore(resolveDirectory: () async => mediaDir),
        openDb: () async => db,
      ),
      readMediaPermission: () async => permission,
      requestMediaPermission: () async => permission,
    );
  }

  /// Open the screen and choose the first card, which is what the operator
  /// does now: discovery and reading are separate actions.
  Future<void> startAndPick(EventIngestViewModel vm) async {
    await vm.start();
    if (vm.volumes.isEmpty) return;
    await vm.selectVolume(vm.volumes.first);
  }

  group('phases', () {
    test('no volume means no card', () async {
      final vm = build();
      await vm.start();
      expect(vm.phase, IngestPhase.noCard);
      addTearDown(vm.dispose);
    });

    test('a mounted but unindexed volume is unreadable, not empty', () async {
      storage.volumes = [
        const ExternalVolume(
          uuid: 'VOL-2',
          description: 'card',
          isRemovable: true,
          isIndexed: false,
        ),
      ];
      final vm = build();
      await startAndPick(vm);
      expect(vm.phase, IngestPhase.unreadable);
      expect(storage.queryCalls, 0, reason: 'nothing to query');
      addTearDown(vm.dispose);
    });

    test('mounted cards land on the picker, and nothing is read', () async {
      const second = ExternalVolume(
        uuid: 'VOL-2',
        description: 'SD card',
        isRemovable: true,
        isIndexed: true,
        mediaStoreVolumeName: 'vol-2',
      );
      storage.volumes = [usableVolume, second];
      storage.rows = [row('A.JPG')];
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.phase, IngestPhase.pickVolume);
      expect(vm.volumes, hasLength(2));
      expect(vm.volume, isNull);
      expect(storage.queryCalls, 0,
          reason: 'a scan on a card nobody chose burns I/O the queue needs');
    });

    test('a single card still gets a list rather than an auto-scan', () async {
      storage.volumes = [usableVolume];
      storage.rows = [row('A.JPG')];
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      // Consistency beats saving a tap: the row is also what tells the operator
      // which card is about to be read.
      expect(vm.phase, IngestPhase.pickVolume);
      expect(vm.volumes, hasLength(1));
      expect(storage.queryCalls, 0);
    });

    test('choosing a card is what starts the read', () async {
      storage.volumes = [usableVolume];
      storage.rows = [row('A.JPG')];
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      await vm.selectVolume(usableVolume);
      expect(vm.phase, IngestPhase.review);
      expect(vm.volume, same(usableVolume));
      expect(storage.queryCalls, greaterThan(0));
    });

    test('back from a chosen card returns to the list, not off the screen',
        () async {
      storage.volumes = [usableVolume];
      storage.rows = [row('A.JPG')];
      final vm = build();
      await startAndPick(vm);
      addTearDown(vm.dispose);

      await vm.backToVolumes();
      expect(vm.phase, IngestPhase.pickVolume);
      expect(vm.volume, isNull);
      expect(vm.scan, isNull);
    });

    test('no cards at all says to insert one', () async {
      storage.volumes = [];
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.phase, IngestPhase.noCard);
      expect(vm.volumes, isEmpty);
    });

    test('an unusable card is listed rather than hidden', () async {
      // Hiding it would look like the card is not seated at all, which sends
      // the operator looking for a hardware fault that is not there.
      storage.volumes = [
        const ExternalVolume(
          uuid: 'VOL-9',
          description: 'SD card',
          isRemovable: true,
          isIndexed: false,
        ),
      ];
      final vm = build();
      await vm.start();
      addTearDown(vm.dispose);

      expect(vm.phase, IngestPhase.pickVolume);
      expect(vm.volumes, hasLength(1));
      expect(vm.volumes.single.isUsable, isFalse);
    });

    test('a denied permission stops before touching the card', () async {
      storage.volumes = [usableVolume];
      final vm = build(permission: PermissionStatus.denied);
      await vm.start();
      expect(vm.phase, IngestPhase.needsPermission);
      expect(storage.queryCalls, 0);
      addTearDown(vm.dispose);
    });

    test('a readable card scans to review with everything preselected',
        () async {
      storage.volumes = [usableVolume];
      storage.rows = [row('A.JPG'), row('B.JPG')];
      final vm = build();
      await startAndPick(vm);

      expect(vm.phase, IngestPhase.review);
      expect(vm.candidates, hasLength(2));
      expect(vm.selectedCount, 2, reason: 'new photos are ticked by default');
      addTearDown(vm.dispose);
    });
  });

  group('selection', () {
    test('toggling an item removes and restores it', () async {
      storage.volumes = [usableVolume];
      storage.rows = [row('A.JPG'), row('B.JPG')];
      final vm = build();
      await startAndPick(vm);

      final first = vm.candidates.first;
      vm.toggleItem(first);
      expect(vm.isSelected(first), isFalse);
      expect(vm.selectedCount, 1);
      vm.toggleItem(first);
      expect(vm.selectedCount, 2);
      addTearDown(vm.dispose);
    });

    test('select none then all', () async {
      storage.volumes = [usableVolume];
      storage.rows = [row('A.JPG'), row('B.JPG')];
      final vm = build();
      await startAndPick(vm);

      vm.selectNone();
      expect(vm.hasSelection, isFalse);
      vm.selectAll();
      expect(vm.selectedCount, 2);
      addTearDown(vm.dispose);
    });

    test('importing nothing reports an error rather than running', () async {
      storage.volumes = [usableVolume];
      storage.rows = [row('A.JPG')];
      final vm = build();
      await startAndPick(vm);
      vm.selectNone();
      await vm.importSelected();

      expect(vm.errorMessage, isNotNull);
      expect(downscaler.calls, 0);
      expect(vm.phase, IngestPhase.review);
      addTearDown(vm.dispose);
    });
  });

  group('folders', () {
    test('a non-DCIM folder is excluded until the operator opts in', () async {
      storage.volumes = [usableVolume];
      storage.rows = [row('A.JPG'), row('B.JPG', folder: 'Pictures')];
      final vm = build();
      await startAndPick(vm);

      expect(vm.candidates, hasLength(1));
      final pictures =
          vm.scan!.folders.firstWhere((f) => f.folder == 'Pictures');
      expect(vm.isFolderIncluded(pictures), isFalse);

      await vm.toggleFolder(pictures);
      expect(vm.candidates, hasLength(2));
      expect(vm.isFolderIncluded(pictures), isTrue);
      addTearDown(vm.dispose);
    });

    test('a default folder cannot be toggled off mid-import', () async {
      storage.volumes = [usableVolume];
      storage.rows = [row('A.JPG')];
      final vm = build();
      await startAndPick(vm);

      final dcim = vm.scan!.folders.first;
      await vm.toggleFolder(dcim);
      expect(vm.candidates, hasLength(1));
      addTearDown(vm.dispose);
    });
  });

  group('import', () {
    test('imports selected photos and reaches safe-to-remove', () async {
      storage.volumes = [usableVolume];
      storage.rows = [row('A.JPG'), row('B.JPG')];
      final vm = build();
      await startAndPick(vm);
      await vm.importSelected();

      expect(vm.phase, IngestPhase.complete);
      expect(vm.report!.imported, 2);
      expect(downscaler.calls, 2);
      addTearDown(vm.dispose);
    });

    test('a rescan after import finds nothing new', () async {
      storage.volumes = [usableVolume];
      storage.rows = [row('A.JPG')];
      final vm = build();
      await startAndPick(vm);
      await vm.importSelected();
      await vm.done();

      // Done returns to the card list; choosing the same card again is where
      // the dedupe shows up.
      expect(vm.phase, IngestPhase.pickVolume);
      await vm.selectVolume(vm.volumes.first);
      expect(vm.phase, IngestPhase.review);
      expect(vm.candidates, isEmpty);
      expect(vm.alreadyImported, 1);
      addTearDown(vm.dispose);
    });

    test('the resolved chain is exposed for the footer preview', () async {
      storage.volumes = [usableVolume];
      storage.rows = [row('A.JPG')];
      final vm = build();
      await startAndPick(vm);
      // Backend flags set autoPrint with no theme or frame configured.
      expect(vm.resolvedSteps, ['print']);
      addTearDown(vm.dispose);
    });
  });

  group('card events', () {
    test('removing the card being read returns to the empty card list',
        () async {
      storage.volumes = [usableVolume];
      storage.rows = [row('A.JPG')];
      final vm = build();
      await startAndPick(vm);
      expect(vm.phase, IngestPhase.review);

      storage.volumes = [];
      cardDetect.controller.add(
        const CardEvent(kind: CardEventKind.unmounted),
      );
      await _until(() => vm.phase == IngestPhase.noCard);

      expect(vm.phase, IngestPhase.noCard);
      expect(vm.volume, isNull);
      expect(vm.scan, isNull);
      expect(vm.selectedCount, 0);
      addTearDown(vm.dispose);
    });

    test('pulling the other card of a reader does not throw away the scan',
        () async {
      const second = ExternalVolume(
        uuid: 'VOL-2',
        description: 'SD card',
        isRemovable: true,
        isIndexed: true,
        mediaStoreVolumeName: 'vol-2',
      );
      storage.volumes = [usableVolume, second];
      storage.rows = [row('A.JPG')];
      final vm = build();
      await startAndPick(vm);
      expect(vm.phase, IngestPhase.review);

      // The untouched card leaves; the one being read is still seated.
      storage.volumes = [usableVolume];
      cardDetect.controller.add(
        const CardEvent(kind: CardEventKind.unmounted),
      );
      await _until(() => vm.volumes.length == 1);

      expect(vm.phase, IngestPhase.review,
          reason: 'a scan in progress must survive the other slot changing');
      expect(vm.volume!.uuid, 'VOL-1');
      expect(vm.candidates, hasLength(1));
      addTearDown(vm.dispose);
    });

    test('an insert lists the new card without reading it', () async {
      storage.volumes = [];
      final vm = build();
      await vm.start();
      expect(vm.phase, IngestPhase.noCard);

      storage.volumes = [usableVolume];
      storage.rows = [row('A.JPG')];
      cardDetect.controller.add(
        const CardEvent(kind: CardEventKind.mounted),
      );
      await _until(() => vm.phase == IngestPhase.pickVolume);

      expect(vm.phase, IngestPhase.pickVolume);
      expect(vm.volumes, hasLength(1));
      expect(storage.queryCalls, 0,
          reason: 'a scan burns I/O on a card nobody chose');
      addTearDown(vm.dispose);
    });

    test('a card pulled mid-import stops the run and reports it', () async {
      storage.volumes = [usableVolume];
      storage.rows = [row('A.JPG'), row('B.JPG'), row('C.JPG')];
      final vm = build();
      await startAndPick(vm);
      expect(vm.phase, IngestPhase.review);
      expect(vm.selectedCount, 3);

      downscaler.onCall = (call) {
        if (call == 1) {
          cardDetect.controller.add(
            const CardEvent(kind: CardEventKind.unmounted),
          );
        }
      };
      await vm.importSelected();

      expect(vm.phase, IngestPhase.complete,
          reason: 'the screen must stay on the report, not blank to no-card');
      expect(vm.stoppedOnCardRemoval, isTrue);
      expect(vm.report!.imported, 1);
      expect(vm.report!.failed, 0);
      expect(vm.importTotal, 3);
      expect(downscaler.calls, 1, reason: 'the other two are never attempted');
      addTearDown(vm.dispose);
    });

    test('the photos left on the card are found again after reinsertion',
        () async {
      storage.volumes = [usableVolume];
      storage.rows = [row('A.JPG'), row('B.JPG'), row('C.JPG')];
      final vm = build();
      await startAndPick(vm);
      downscaler.onCall = (call) {
        if (call == 1) {
          cardDetect.controller.add(
            const CardEvent(kind: CardEventKind.unmounted),
          );
        }
      };
      await vm.importSelected();
      downscaler.onCall = null;

      // Operator reinserts the card and chooses it again.
      await vm.done();
      await vm.selectVolume(vm.volumes.first);
      expect(vm.phase, IngestPhase.review);
      expect(vm.candidates, hasLength(2),
          reason: 'rolled-back rows must not read as already imported');
      expect(vm.alreadyImported, 1);

      await vm.importSelected();
      expect(vm.report!.imported, 2);
      expect(vm.stoppedOnCardRemoval, isFalse);
      addTearDown(vm.dispose);
    });

    test('dispose stops listening', () async {
      final vm = build();
      await vm.start();
      vm.dispose();
      // Emitting after dispose must not call notifyListeners on a dead model.
      cardDetect.controller.add(
        const CardEvent(kind: CardEventKind.unmounted),
      );
      await Future<void>.delayed(Duration.zero);
    });
  });

  test('source rows record the sdcard source kind', () async {
    storage.volumes = [usableVolume];
    storage.rows = [row('A.JPG')];
    final vm = build();
    await vm.start();
    await vm.selectVolume(vm.volumes.first);
    await vm.importSelected();

    final rows = await db.database.query('evp_media_items');
    expect(rows, hasLength(1));
    expect(rows.single['source'], MediaSource.sdCard);
    addTearDown(vm.dispose);
  });
}

/// Waits for [condition], so a test does not depend on how many event-loop
/// turns a card-detect event takes to be reconciled.
Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
