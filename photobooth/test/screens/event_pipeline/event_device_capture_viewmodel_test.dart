import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_pipeline/media_item.dart';
import 'package:photobooth/screens/event_pipeline/event_device_capture_viewmodel.dart';
import 'package:photobooth/services/event_pipeline/capture/event_capture_coordinator.dart';
import 'package:photobooth/services/event_pipeline/capture/event_capture_source.dart';
import 'package:photobooth/services/event_pipeline/capture/event_device_capture_uploader.dart';
import 'package:photobooth/utils/app_strings.dart';

class FakeCommit extends EventCaptureCoordinator {
  FakeCommit({this.storage = true});

  bool storage;
  CaptureCommitOutcome next = const CaptureCommitOutcome(
    queued: true,
    message: 'Added to queue',
  );
  CapturedShot? last;
  String? lastKind;

  @override
  bool get hasStorage => storage;

  @override
  Future<CaptureCommitOutcome> commitShot(
    CapturedShot shot, {
    String sourceKind = MediaSource.camera,
    Future<String?>? eventId,
  }) async {
    last = shot;
    lastKind = sourceKind;
    return next;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late FakeCommit commit;
  late EventDeviceCaptureUploader remote;
  var uploads = 0;

  EventDeviceCaptureUploader makeRemote({
    CaptureCommitOutcome outcome = const CaptureCommitOutcome(
      queued: true,
      message: 'Added to queue',
    ),
  }) {
    return EventDeviceCaptureUploader(
      hooks: EventDeviceCaptureUploadHooks(
        kioskCode: () async => 'K1',
        createSession: (_) async {
          uploads++;
          if (!outcome.queued) throw StateError(outcome.message);
          return <String, dynamic>{'id': 's$uploads'};
        },
        updateSession: (_, __) async {},
      ),
    );
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fz_evp_devcam_');
    commit = FakeCommit();
    uploads = 0;
    remote = makeRemote();
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<File> jpegOnDisk() async {
    final file = File('${root.path}/shot.jpg');
    await file.writeAsBytes(Uint8List.fromList(const [0xFF, 0xD8, 1, 2, 3]));
    return file;
  }

  EventDeviceCaptureViewModel build({
    EventStillPicker? pickStill,
    FakeCommit? coordinator,
    EventDeviceCaptureUploader? uploader,
  }) {
    return EventDeviceCaptureViewModel(
      coordinator: coordinator ?? commit,
      pickStill: pickStill,
      uploader: uploader ?? remote,
    );
  }

  test('a cancelled picker leaves nothing pending', () async {
    final vm = build(pickStill: () async => null);
    await vm.shutter();
    expect(vm.hasPending, isFalse);
    expect(vm.queuedCount, 0);
  });

  test('accept with nothing pending is reported', () async {
    final vm = build(pickStill: () async => null);
    final outcome = await vm.accept();
    expect(outcome.queued, isFalse);
    expect(outcome.message, AppStrings.eventDeviceCaptureNothing);
  });

  test('a file still queues through the local ledger', () async {
    final file = await jpegOnDisk();
    final vm = build(pickStill: () async => XFile(file.path));
    await vm.shutter();
    expect(vm.hasPending, isTrue);

    final outcome = await vm.accept();
    expect(outcome.queued, isTrue);
    expect(vm.queuedCount, 1);
    expect(vm.hasPending, isFalse);
    expect(commit.last!.originalPath, file.path);
    expect(commit.lastKind, MediaSource.camera);
    expect(uploads, 0);
  });

  test('retake drops the pending still', () async {
    final file = await jpegOnDisk();
    final vm = build(pickStill: () async => XFile(file.path));
    await vm.shutter();
    vm.retake();
    expect(vm.hasPending, isFalse);
    expect(vm.queuedCount, 0);
  });

  test('a failed commit keeps the still for another try', () async {
    commit.next = const CaptureCommitOutcome(
      queued: false,
      message: 'Already in the queue',
    );
    final file = await jpegOnDisk();
    final vm = build(pickStill: () async => XFile(file.path));
    await vm.shutter();
    final outcome = await vm.accept();
    expect(outcome.queued, isFalse);
    expect(vm.hasPending, isTrue);
    expect(vm.queuedCount, 0);
    expect(vm.message, 'Already in the queue');
  });

  test('in-memory stills upload when there is no local ledger', () async {
    commit.storage = false;
    final vm = build(
      pickStill: () async => XFile.fromData(
        Uint8List.fromList(const [0xFF, 0xD8, 9]),
        name: 'cam.jpg',
        mimeType: 'image/jpeg',
      ),
    );
    await vm.shutter();
    expect(vm.pending?.inlineBytes, isNotNull);
    final outcome = await vm.accept();
    expect(outcome.queued, isTrue);
    expect(uploads, 1);
    expect(commit.last, isNull);
  });

  test('a file still uploads when storage is gone', () async {
    commit.storage = false;
    final file = await jpegOnDisk();
    final vm = build(pickStill: () async => XFile(file.path));
    await vm.shutter();
    expect(await vm.accept(), isA<CaptureCommitOutcome>());
    expect(vm.queuedCount, 1);
    expect(uploads, 1);
  });

  test('an empty still is ignored', () async {
    final vm = build(
      pickStill: () async => XFile.fromData(
        Uint8List(0),
        name: 'empty.jpg',
      ),
    );
    await vm.shutter();
    expect(vm.hasPending, isFalse);
  });

  test('a picker that throws stays on the screen', () async {
    final vm = build(pickStill: () async => throw StateError('denied'));
    await vm.shutter();
    expect(vm.message, AppStrings.eventDeviceCaptureNothing);
    expect(vm.hasPending, isFalse);
  });

  test('a second shutter is ignored while the first is open', () async {
    final gate = Completer<XFile?>();
    final vm = build(pickStill: () => gate.future);
    final first = vm.shutter();
    await vm.shutter();
    gate.complete(null);
    await first;
    expect(vm.hasPending, isFalse);
  });

  test('accept is ignored while a shutter is in flight', () async {
    final gate = Completer<XFile?>();
    final vm = build(pickStill: () => gate.future);
    final first = vm.shutter();
    final outcome = await vm.accept();
    expect(outcome.message, isEmpty);
    gate.complete(null);
    await first;
  });

  test('a missing file falls back to a zero-length read', () async {
    commit.storage = false;
    remote = EventDeviceCaptureUploader(
      hooks: EventDeviceCaptureUploadHooks(
        kioskCode: () async => 'K1',
        createSession: (_) async => throw StateError('should not upload empty'),
        updateSession: (_, __) async {},
      ),
    );
    final vm = build(
      pickStill: () async => XFile('${root.path}/missing.jpg'),
      uploader: remote,
    );
    await vm.shutter();
    expect(vm.hasPending, isFalse);
  });

  test('deleting the file after capture uploads nothing from disk', () async {
    final file = await jpegOnDisk();
    final vm = build(pickStill: () async => XFile(file.path));
    await vm.shutter();
    await file.delete();
    commit.storage = false;
    final outcome = await vm.accept();
    expect(outcome.queued, isFalse);
    expect(outcome.message, contains('not where the camera said'));
  });

  test('the default picker fails closed without a camera plugin', () async {
    final vm = EventDeviceCaptureViewModel(
      coordinator: commit,
      uploader: remote,
    );
    await vm.shutter();
    expect(vm.message, AppStrings.eventDeviceCaptureNothing);
  });

  test('the default uploader factory can be constructed', () {
    expect(
      EventDeviceCaptureViewModel.defaultUploader(),
      isA<EventDeviceCaptureUploader>(),
    );
  });

  test('a remote uploader is created on first use', () async {
    var made = 0;
    commit.storage = false;
    final vm = EventDeviceCaptureViewModel(
      coordinator: commit,
      pickStill: () async => XFile.fromData(
        Uint8List.fromList(const [0xFF, 0xD8, 4]),
        name: 'cam.jpg',
      ),
      createUploader: () {
        made++;
        return remote;
      },
    );
    await vm.shutter();
    await vm.accept();
    expect(made, 1);
    expect(vm.queuedCount, 1);
  });
}
