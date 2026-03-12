import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

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
          final name = path.basename(entity.path).toLowerCase();
          if (_shouldDeleteTempImage(name)) {
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

  static bool _shouldDeleteTempImage(String fileName) {
    final isImage = fileName.endsWith('.jpg') ||
        fileName.endsWith('.jpeg') ||
        fileName.endsWith('.png') ||
        fileName.endsWith('.gif') ||
        fileName.endsWith('.webp');
    if (!isImage) {
      return false;
    }

    const prefixes = [
      'upload_',
      'transformed_',
      'print_',
      'capture_',
      'captured_',
      'photo_',
      'img_',
      'pxl_',
      'cap',
      'camera_',
    ];

    for (final prefix in prefixes) {
      if (fileName.startsWith(prefix)) {
        return true;
      }
    }

    if (fileName.contains('capture') || fileName.contains('camera')) {
      return true;
    }

    return false;
  }
}
