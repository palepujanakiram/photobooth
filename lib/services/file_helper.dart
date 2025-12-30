import 'dart:io' if (dart.library.html) 'dart:html' as io;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

/// Helper class for file operations that work on both mobile and web
class FileHelper {
  /// Gets a temporary directory path (mobile only)
  static Future<String> getTempDirectoryPath() async {
    if (kIsWeb) {
      throw UnsupportedError('getTempDirectoryPath is not available on web');
    }
    final tempDir = await getTemporaryDirectory();
    return tempDir.path;
  }

  /// Creates a File instance (mobile only)
  static dynamic createFile(String path) {
    if (kIsWeb) {
      throw UnsupportedError('createFile is not available on web');
    }
    // On mobile, io refers to dart:io
    return (io.File as dynamic)(path);
  }
}

