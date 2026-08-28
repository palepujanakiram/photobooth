import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/kiosk_info_model.dart';
import 'package:photobooth/screens/splash/app_splash_kiosk_bind_helpers.dart';
import 'package:photobooth/services/catalog_disk_cache.dart';
import 'package:photobooth/services/kiosk_info_disk_cache.dart';
import 'package:photobooth/utils/app_strings.dart';

void main() {
  late Directory dir;
  late KioskInfoDiskCache cache;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('splash_kiosk_bind_');
    cache = KioskInfoDiskCache(
      diskCache: CatalogDiskCache(resolveDirectory: () async => dir),
    );
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('empty code fails', () async {
    final r = await resolveSplashKioskByCode(
      code: '  ',
      fetchOnline: (_) async => throw StateError('no fetch'),
      cache: cache,
    );
    expect(r.isOk, isFalse);
    expect(r.errorMessage, AppStrings.splashEnterKioskCode);
  });

  test('online hit is cached and returned', () async {
    const info = KioskInfoModel(
      id: 'k1',
      code: 'ABC',
      paymentEnabled: false,
    );
    final r = await resolveSplashKioskByCode(
      code: 'abc',
      fetchOnline: (code) async {
        expect(code, 'ABC');
        return info;
      },
      cache: cache,
    );
    expect(r.isOk, isTrue);
    expect(r.fromCache, isFalse);
    expect(r.kiosk!.id, 'k1');
    final disk = await cache.read('ABC');
    expect(disk?.id, 'k1');
  });

  test('offline uses disk cache when fetch returns null', () async {
    await cache.save(
      const KioskInfoModel(id: 'k9', code: 'OFF1', name: 'Cached'),
    );
    final r = await resolveSplashKioskByCode(
      code: 'OFF1',
      fetchOnline: (_) async => null,
      cache: cache,
    );
    expect(r.isOk, isTrue);
    expect(r.fromCache, isTrue);
    expect(r.kiosk!.name, 'Cached');
  });

  test('offline uses disk cache when fetch throws', () async {
    await cache.save(const KioskInfoModel(id: 'k2', code: 'OFF2'));
    final r = await resolveSplashKioskByCode(
      code: 'OFF2',
      fetchOnline: (_) async => throw Exception('no network'),
      cache: cache,
    );
    expect(r.isOk, isTrue);
    expect(r.fromCache, isTrue);
  });

  test('never-seen code with failed fetch returns unavailable message',
      () async {
    final r = await resolveSplashKioskByCode(
      code: 'NEW1',
      fetchOnline: (_) async => null,
      cache: cache,
    );
    expect(r.isOk, isFalse);
    expect(r.errorMessage, AppStrings.splashKioskCodeUnavailable);
  });

  test('resolveSplashKioskByCode uses default disk cache', () async {
    final previous = CatalogDiskCache.supportDirectory;
    CatalogDiskCache.supportDirectory = () async => dir;
    addTearDown(() => CatalogDiskCache.supportDirectory = previous);
    const info = KioskInfoModel(id: 'k1', code: 'DEF');
    final r = await resolveSplashKioskByCode(
      code: 'def',
      fetchOnline: (_) async => info,
    );
    expect(r.isOk, isTrue);
    expect(r.fromCache, isFalse);
  });
}
