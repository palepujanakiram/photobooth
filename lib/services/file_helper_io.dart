import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// IO (mobile/desktop) implementation of FileHelper
class FileHelper {
  /// Gets a temporary directory path
  static Future<String> getTempDirectoryPath() async {
    final tempDir = await getTemporaryDirectory();
    return tempDir.path;
  }

  /// Creates a File instance
  static File createFile(String path) {
    return File(path);
  }
}
