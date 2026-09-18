import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/event_pipeline/ingest/card_detect_channel.dart';
import 'package:photobooth/services/event_pipeline/ingest/event_storage_channel.dart';
import 'package:photobooth/services/event_pipeline/ingest/media_store_ingest_source.dart';
import 'package:photobooth/services/event_pipeline/ingest/platform_image_downscaler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Installs a fake platform handler for one channel and removes it after.
  void mockChannel(
    String name,
    Future<Object?>? Function(MethodCall call) handler,
  ) {
    final channel = MethodChannel(name);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
  }

  const volume = ExternalVolume(
    uuid: '1E6F-0961',
    description: 'SD card',
    isRemovable: true,
    isIndexed: true,
    mediaStoreVolumeName: '1e6f-0961',
    directRead: false,
  );

  Map<Object?, Object?> row({
    String name = 'IMG_6624.JPG',
    String folder = 'DCIM/100CANON',
    int size = 6921200,
    int modifiedMs = 1691754732000,
    int? takenMs = 1691754731900,
    String mime = 'image/jpeg',
  }) {
    return <Object?, Object?>{
      'uri': 'content://media/1e6f-0961/images/media/1',
      'displayName': name,
      'relativePath': '$folder/$name',
      'folder': folder,
      'sizeBytes': size,
      'modifiedAtMs': modifiedMs,
      'capturedAtMs': takenMs,
      'mimeType': mime,
      'width': 6000,
      'height': 4000,
      'orientation': 0,
    };
  }

  group('ExternalVolume', () {
    test('is usable only when removable and indexed', () {
      expect(volume.isUsable, isTrue);
      expect(
        ExternalVolume.fromMap(const {
          'uuid': 'X',
          'isRemovable': true,
          'isIndexed': false,
        }).isUsable,
        isFalse,
        reason: 'mounted but not indexed must not look like an empty card',
      );
    });

    test('records that direct read is unavailable', () {
      final parsed = ExternalVolume.fromMap(const {
        'uuid': 'X',
        'isRemovable': true,
        'isIndexed': true,
        'mediaStoreVolumeName': 'x',
        'directRead': false,
      });
      expect(parsed.directRead, isFalse);
    });
  });

  group('MediaStoreIngestSource', () {
    test('maps a cursor row into a candidate', () async {
      mockChannel(EventStorageChannel.channelName, (call) async {
        if (call.method == 'queryImages') return [row()];
        return null;
      });

      final source = MediaStoreIngestSource(
        volume: volume,
        scanFolders: const ['DCIM'],
      );
      final all = await source.listAll();
      expect(all, hasLength(1));
      final c = all.single;
      expect(c.displayName, 'IMG_6624.JPG');
      expect(c.relativePath, 'DCIM/100CANON/IMG_6624.JPG');
      expect(c.folder, 'DCIM/100CANON');
      expect(c.sizeBytes, 6921200);
      expect(c.capturedAtMs, 1691754731900);
    });

    test('the tier-1 key includes size and mtime', () async {
      mockChannel(EventStorageChannel.channelName, (call) async {
        if (call.method == 'queryImages') return [row()];
        return null;
      });
      final source = MediaStoreIngestSource(
        volume: volume,
        scanFolders: const ['DCIM'],
      );
      final c = (await source.listAll()).single;
      expect(
        c.sourceRef,
        '1E6F-0961:DCIM/100CANON/IMG_6624.JPG:6921200:1691754732000',
      );
    });

    test('drops rows with no size or path rather than importing junk', () async {
      mockChannel(EventStorageChannel.channelName, (call) async {
        if (call.method != 'queryImages') return null;
        return [
          row(),
          <Object?, Object?>{'uri': 'content://x', 'relativePath': ''},
          <Object?, Object?>{
            'uri': 'content://y',
            'relativePath': 'DCIM/a.jpg',
            'sizeBytes': 0,
          },
        ];
      });
      final source = MediaStoreIngestSource(
        volume: volume,
        scanFolders: const ['DCIM'],
      );
      expect(await source.listAll(), hasLength(1));
    });

    test('an unindexed volume lists empty instead of querying', () async {
      var queried = false;
      mockChannel(EventStorageChannel.channelName, (call) async {
        queried = true;
        return <Object?>[];
      });
      final source = MediaStoreIngestSource(
        volume: const ExternalVolume(
          uuid: 'X',
          description: 'card',
          isRemovable: true,
          isIndexed: false,
        ),
        scanFolders: const ['DCIM'],
      );
      expect(await source.listAll(), isEmpty);
      expect(queried, isFalse);
    });

    test('readRange forwards to the platform', () async {
      late MethodCall seen;
      mockChannel(EventStorageChannel.channelName, (call) async {
        seen = call;
        if (call.method == 'readRange') {
          return Uint8List.fromList([1, 2, 3]);
        }
        return [row()];
      });
      final source = MediaStoreIngestSource(
        volume: volume,
        scanFolders: const ['DCIM'],
      );
      final c = (await source.listAll()).single;
      final bytes = await source.readRange(c, 64, 128);
      expect(bytes, [1, 2, 3]);
      expect(seen.arguments['offset'], 64);
      expect(seen.arguments['length'], 128);
    });

    test('a platform failure degrades to an empty list, not a crash', () async {
      mockChannel(EventStorageChannel.channelName, (call) async {
        throw PlatformException(code: 'event_storage_error', message: 'nope');
      });
      final source = MediaStoreIngestSource(
        volume: volume,
        scanFolders: const ['DCIM'],
      );
      expect(await source.listAll(), isEmpty);
    });
  });

  group('MediaStoreSettleWatcher', () {
    test('waits for the count to stop changing', () async {
      // The measured curve: a card mounts empty and fills in over ~11s.
      final counts = <int>[0, 159, 192, 254, 254, 254];
      var i = 0;
      final watcher = MediaStoreSettleWatcher(stableReadsRequired: 3);
      final settled = await watcher.awaitSettled(
        count: () async => counts[i < counts.length ? i++ : counts.length - 1],
        delay: (_) async {},
      );
      expect(settled, 254);
    });

    test('does not settle on a zero count', () async {
      // Scanning immediately after mount reports 0 on a full card; treating that
      // as settled is exactly the bug this class exists to prevent.
      var calls = 0;
      final watcher = MediaStoreSettleWatcher(
        stableReadsRequired: 2,
        timeout: const Duration(milliseconds: 1),
      );
      final settled = await watcher.awaitSettled(
        count: () async {
          calls++;
          return 0;
        },
        delay: (_) async {},
      );
      expect(settled, 0);
      expect(calls, greaterThan(0));
    });

    test('reports progress while still scanning', () async {
      final counts = <int>[10, 20, 20, 20];
      var i = 0;
      final seen = <bool>[];
      await MediaStoreSettleWatcher(stableReadsRequired: 3).awaitSettled(
        count: () async => counts[i < counts.length ? i++ : counts.length - 1],
        delay: (_) async {},
        onProgress: (_, settled) => seen.add(settled),
      );
      expect(seen.first, isFalse, reason: 'still scanning at the start');
      expect(seen.last, isTrue);
    });
  });

  group('PlatformImageDownscaler', () {
    test('returns the derivative and its dimensions', () async {
      mockChannel(PlatformImageDownscaler.channelName, (call) async {
        expect(call.method, 'downscale');
        expect(call.arguments['targetShortSide'], 1920);
        return <Object?, Object?>{
          'bytes': Uint8List.fromList([1, 2, 3, 4]),
          'width': 2880,
          'height': 1920,
        };
      });
      final result = await PlatformImageDownscaler().downscale(
        sourceUri: 'content://x',
        targetShortSide: 1920,
      );
      expect(result.bytes, hasLength(4));
      expect(result.width, 2880);
      expect(result.height, 1920);
    });

    test('empty output throws so the item is marked failed, not imported',
        () async {
      mockChannel(PlatformImageDownscaler.channelName, (call) async {
        return <Object?, Object?>{'bytes': Uint8List(0)};
      });
      expect(
        () => PlatformImageDownscaler()
            .downscale(sourceUri: 'content://x', targetShortSide: 1920),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('CardEvent', () {
    test('parses each kind', () {
      expect(
        CardEvent.fromMap(const {'kind': 'mounted'})!.kind,
        CardEventKind.mounted,
      );
      expect(
        CardEvent.fromMap(const {'kind': 'usbDetached'})!.kind,
        CardEventKind.usbDetached,
      );
    });

    test('an unknown kind is dropped', () {
      expect(CardEvent.fromMap(const {'kind': 'wat'}), isNull);
    });

    test('classifies inserts and removals', () {
      expect(CardEvent.fromMap(const {'kind': 'mounted'})!.isInsert, isTrue);
      expect(
        CardEvent.fromMap(const {'kind': 'usbAttached'})!.isInsert,
        isTrue,
      );
      expect(CardEvent.fromMap(const {'kind': 'unmounted'})!.isRemoval, isTrue);
    });

    test('carries the mass-storage flag from the USB interface class', () {
      final event = CardEvent.fromMap(const {
        'kind': 'usbAttached',
        'vendorId': 1507,
        'productId': 1873,
        'isMassStorage': true,
      });
      expect(event!.isMassStorage, isTrue);
      expect(event.vendorId, 1507);
    });
  });
}
