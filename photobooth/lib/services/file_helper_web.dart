/// Web implementation of FileHelper
class FileHelper {
  /// Gets a temporary directory path (not available on web)
  static Future<String> getTempDirectoryPath() async {
    throw UnsupportedError('getTempDirectoryPath is not available on web');
  }

  /// Ensures a directory exists (not available on web)
  static Future<void> ensureDirectory(String dirPath) async {
    throw UnsupportedError('ensureDirectory is not available on web');
  }

  /// Creates a File instance (not available on web)
  static dynamic createFile(String path) {
    throw UnsupportedError('createFile is not available on web');
  }

  /// No-op on web
  static Future<void> cleanupTempImages() async {
    return;
  }
}
