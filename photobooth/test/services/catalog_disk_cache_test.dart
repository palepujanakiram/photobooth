import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photobooth/services/catalog_disk_cache.dart';

void main() {
  late Directory dir;
  late CatalogDiskCache cache;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('catalog_cache_');
    cache = CatalogDiskCache(resolveDirectory: () async => dir);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('sanitizeKey rejects empty and path junk', () {
    expect(CatalogDiskCache.sanitizeKey(''), isNull);
    expect(CatalogDiskCache.sanitizeKey('../x'), isNull);
    expect(CatalogDiskCache.sanitizeKey('themes_K1'), 'themes_K1');
  });

  test('write and read JSON map and list', () async {
    await cache.writeJson('themes_K1', [
      {'id': 't1'},
    ]);
    final raw = await cache.readJson('themes_K1');
    expect(raw, isA<List<dynamic>>());
    expect((raw as List).first['id'], 't1');

    await cache.writeJson('settings_K1', {'initialPrice': 99});
    final map = await cache.readJson('settings_K1');
    expect((map as Map)['initialPrice'], 99);
  });

  test('readJson returns null for missing, empty, and corrupt files', () async {
    expect(await cache.readJson('missing'), isNull);
    final empty = File('${dir.path}/empty.json');
    await empty.writeAsString('  ');
    expect(await cache.readJson('empty'), isNull);
    final bad = File('${dir.path}/bad.json');
    await bad.writeAsString('{not-json');
    expect(await cache.readJson('bad'), isNull);
  });

  test('delete removes file and ignores missing', () async {
    await cache.writeJson('gone', {'a': 1});
    await cache.delete('gone');
    expect(await cache.readJson('gone'), isNull);
    await cache.delete('gone');
  });

  test('rejects unsafe keys without throwing', () async {
    await cache.writeJson('../nope', {'x': 1});
    expect(await cache.readJson('../nope'), isNull);
  });

  test('directory failure is swallowed', () async {
    final broken = CatalogDiskCache(
      resolveDirectory: () async => throw StateError('no dir'),
    );
    await broken.writeJson('k', {'a': 1});
    expect(await broken.readJson('k'), isNull);
    await broken.delete('k');
  });

  test('write and delete failures are swallowed', () async {
    await Directory('${dir.path}/blocked.json').create();
    await cache.writeJson('blocked', {'a': 1});
    await cache.delete('blocked');
  });

  test('default catalog directory is created', () async {
    final root = await Directory.systemTemp.createTemp('catalog_support_');
    addTearDown(() async {
      CatalogDiskCache.supportDirectory = getApplicationSupportDirectory;
      if (await root.exists()) await root.delete(recursive: true);
    });
    CatalogDiskCache.supportDirectory = () async => root;
    final cache2 = CatalogDiskCache();
    await cache2.writeJson('themes_K1', {'ok': true});
    expect(await cache2.readJson('themes_K1'), {'ok': true});
    expect(await Directory('${root.path}/catalog').exists(), isTrue);
  });
}
