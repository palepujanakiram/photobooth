import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../utils/file_helper_temp_cleanup.dart';

/// IO (mobile/desktop) implementation of FileHelper
class FileHelper {
  /// Gets a temporary directory path
  static Future<String> getTempDirectoryPath() async {
    final tempDir = await getTemporaryDirectory();
    return tempDir.path;
  }

  /// Ensures a directory exists (creates it and parents if needed).
  static Future<void> ensureDirectory(String dirPath) async {
    await Directory(dirPath).create(recursive: true);
  }

  /// Creates a File instance
  static File createFile(String path) {
    return File(path);
  }

  /// Deletes temporary image files created by capture/transform flows.
  /// Errors are ignored to avoid impacting user experience.
  static Future<void> cleanupTempImages() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final dir = Directory(tempDir.path);
      if (!await dir.exists()) {
        return;
      }

      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) {
          final name = path.basename(entity.path);
          if (shouldDeleteTempImageFileName(name)) {
            try {
              await entity.delete();
            } catch (_) {
              // Ignore delete errors
            }
          }
        }
      }
    } catch (_) {
      // Ignore all errors
    }
  }

}
