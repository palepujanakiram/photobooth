/// Stub implementation that throws errors
/// This file should never be used at runtime
class FileHelper {
  static Future<String> getTempDirectoryPath() async {
    throw UnsupportedError('Platform not supported');
  }

  static dynamic createFile(String path) {
    throw UnsupportedError('Platform not supported');
  }

  static Future<void> cleanupTempImages() async {
    return;
  }
}
