import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/kiosk_disk_guard.dart';
import 'package:photobooth/services/local_kiosk_models.dart';
import 'package:photobooth/services/local_kiosk_store.dart';
import 'package:photobooth/services/local_media_store.dart';
import 'package:photobooth/utils/app_strings.dart';

void main() {
  late Directory dir;
  late LocalKioskStore store;
  late LocalMediaStore media;
  var clock = 1000;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fz_disk_');
    clock = 1000;
    store = LocalKioskStore(
      resolveDirectory: () async => Directory('${dir.path}/kiosk'),
      nowMs: () => clock,
    );
    media = LocalMediaStore(
      resolveDirectory: () async => Directory('${dir.path}/media'),
    );
  });

  tearDown(() async {
    LocalKioskStore.resetInstance();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('null stores are not critical', () async {
    final guard = KioskDiskGuard();
    final status = await guard.measure();
    expect(status.isCritical, isFalse);
    expect(status.unsyncedBytes, 0);
    expect(KioskDiskGuard.shouldBlockNewSessions(status), isFalse);
    expect(await guard.pruneSynced(), 0);
    expect(status.staffMessage, AppStrings.staffDiskFull);
    expect(
      await KioskDiskGuard(store: store, media: media).pruneSynced(),
      0,
    );
  });

  test('unsynced bytes over the cap block new sessions', () async {
    await media.putBytes(
      const LocalMediaRef(prefix: 'generated', filename: 'a.jpg'),
      Uint8List.fromList(const [1, 2, 3, 4, 5]),
    );
    final guard = KioskDiskGuard(
      store: store,
      media: media,
      capBytes: 4,
    );
    final status = await guard.measure();
    expect(status.unsyncedBytes, 5);
    expect(status.isCritical, isTrue);
    expect(KioskDiskGuard.shouldBlockNewSessions(status), isTrue);
  });

  test('prunes old synced files and skips open outbox rows', () async {
    const oldRef = LocalMediaRef(prefix: 'generated', filename: 'old.jpg');
    const freshRef = LocalMediaRef(prefix: 'generated', filename: 'new.jpg');
    const pendingRef = LocalMediaRef(prefix: 'previews', filename: 'p.jpg');
    await media.putBytes(oldRef, const [1]);
    await media.putBytes(freshRef, const [2, 2]);
    await media.putBytes(pendingRef, const [3, 3, 3]);
    await store.markAssetSynced(oldRef.relativePath, atMs: 1);
    await store.markAssetSynced(freshRef.relativePath, atMs: 950);
    await store.markAssetSynced(pendingRef.relativePath, atMs: 1);
    await store.enqueueOutbox(
      entityType: KioskOutboxEntity.asset,
      entityId: pendingRef.relativePath,
      payload: {'prefix': pendingRef.prefix, 'filename': pendingRef.filename},
    );
    await store.markAssetSynced('nopath', atMs: 1);

    final guard = KioskDiskGuard(
      store: store,
      media: media,
      retention: const Duration(milliseconds: 100),
      nowMs: () => 1000,
    );
    expect(await guard.pruneSynced(), 1);
    expect(await media.getFile(oldRef), isNull);
    expect(await media.getFile(freshRef), isNotNull);
    expect(await media.getFile(pendingRef), isNotNull);
    final leftover = await store.syncedAssets();
    expect(leftover.containsKey(oldRef.relativePath), isFalse);
    expect(leftover.containsKey('nopath'), isFalse);
    expect(leftover.containsKey(freshRef.relativePath), isTrue);

    final after = await guard.measure();
    expect(after.syncedBytes, greaterThan(0));
  });
}
