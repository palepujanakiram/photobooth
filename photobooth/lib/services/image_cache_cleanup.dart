import 'dart:io';

import '../utils/logger.dart';

/// Deletes oldest cache files until [currentSize] is at or below [maxSizeBytes].
int evictOldestImageCacheFiles({
  required List<({File file, FileStat stat})> fileInfo,
  required int currentSize,
  required int maxSizeBytes,
}) {
  var size = currentSize;
  for (final info in fileInfo) {
    if (size <= maxSizeBytes) break;
    try {
      if (info.file.existsSync()) {
        info.file.deleteSync();
        size -= info.stat.size;
        AppLogger.debug(
          'ImageCacheService: deleted old cache file: ${info.file.path}',
        );
      }
    } catch (e, st) {
      if (e is FileSystemException && e.osError?.errorCode == 2) {
        continue;
      }
      if (e is PathNotFoundException) {
        continue;
      }
      AppLogger.error(
        'ImageCacheService: error deleting cache file',
        error: e,
        stackTrace: st,
      );
    }
  }
  return size;
}
