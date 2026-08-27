import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/kiosk_info_model.dart';
import 'package:photobooth/services/catalog_disk_cache.dart';
import 'package:photobooth/services/kiosk_info_disk_cache.dart';

void main() {
  late Directory dir;
  late KioskInfoDiskCache cache;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kiosk_info_disk_');
    cache = KioskInfoDiskCache(
      diskCache: CatalogDiskCache(resolveDirectory: () async => dir),
    );
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('diskKey normalizes code', () {
    expect(KioskInfoDiskCache.diskKey(' ab-1 '), 'kiosk_AB-1');
    expect(KioskInfoDiskCache.diskKey('a/b'), 'kiosk_A_B');
  });

  test('save and read round-trip', () async {
    const info = KioskInfoModel(
      id: 'k1',
      code: 'BOOTH1',
      name: 'Lobby',
      paymentEnabled: true,
      classicPhotosEnabled: false,
      operatingMode: KioskInfoModel.operatingModeOffline,
      initialPrice: 199,
    );
    await cache.save(info);
    final loaded = await cache.read('booth1');
    expect(loaded, isNotNull);
    expect(loaded!.id, 'k1');
    expect(loaded.code, 'BOOTH1');
    expect(loaded.name, 'Lobby');
    expect(loaded.paymentEnabled, isTrue);
    expect(loaded.classicPhotosEnabled, isFalse);
    expect(loaded.isOperatingModeOffline, isTrue);
    expect(loaded.initialPrice, 199);
  });

  test('read returns null when missing or invalid', () async {
    expect(await cache.read('MISSING'), isNull);
    expect(await cache.read(''), isNull);
  });

  test('delete removes entry', () async {
    await cache.save(const KioskInfoModel(id: 'k1', code: 'X1'));
    await cache.delete('X1');
    expect(await cache.read('X1'), isNull);
  });
}
