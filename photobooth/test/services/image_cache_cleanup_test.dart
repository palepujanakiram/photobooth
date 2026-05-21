import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/image_cache_cleanup.dart';

void main() {
  test('evictOldestImageCacheFiles stops when under max size', () {
    final dir = Directory.systemTemp.createTempSync('cache_evict_test');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    final f1 = File('${dir.path}/a.dat')..writeAsBytesSync(List.filled(100, 1));
    final f2 = File('${dir.path}/b.dat')..writeAsBytesSync(List.filled(100, 1));
    final info = [
      (file: f1, stat: f1.statSync()),
      (file: f2, stat: f2.statSync()),
    ];

    final remaining = evictOldestImageCacheFiles(
      fileInfo: info,
      currentSize: 150,
      maxSizeBytes: 200,
    );
    expect(remaining, 150);
    expect(f1.existsSync(), isTrue);
    expect(f2.existsSync(), isTrue);
  });

  test('evictOldestImageCacheFiles deletes oldest until under cap', () {
    final dir = Directory.systemTemp.createTempSync('cache_evict_test');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    final f1 = File('${dir.path}/a.dat')..writeAsBytesSync(List.filled(80, 1));
    final f2 = File('${dir.path}/b.dat')..writeAsBytesSync(List.filled(80, 1));
    final info = [
      (file: f1, stat: f1.statSync()),
      (file: f2, stat: f2.statSync()),
    ];

    final remaining = evictOldestImageCacheFiles(
      fileInfo: info,
      currentSize: 160,
      maxSizeBytes: 100,
    );
    expect(remaining, lessThanOrEqualTo(100));
    expect(f1.existsSync() || f2.existsSync(), isTrue);
  });

  test('evictOldestImageCacheFiles skips files deleted before eviction', () {
    final dir = Directory.systemTemp.createTempSync('cache_evict_test');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    final f1 = File('${dir.path}/gone.dat')..writeAsBytesSync([1]);
    final stat = f1.statSync();
    f1.deleteSync();
    final info = [(file: f1, stat: stat)];

    final remaining = evictOldestImageCacheFiles(
      fileInfo: info,
      currentSize: 50,
      maxSizeBytes: 10,
    );
    expect(remaining, 50);
  });
}
