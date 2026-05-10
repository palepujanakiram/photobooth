class CameraException implements Exception {
  final String message;
  CameraException(this.message);

  @override
  String toString() => 'CameraException: $message';
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, [this.statusCode]);

  /// Text for dialogs and banners. Hides minified JS engine errors from 500 responses.
  String get userFacingMessage {
    if (statusCode == 500) {
      final m = message;
      if (m.contains('before initialization') ||
          m.contains('ReferenceError') ||
          m.contains("Cannot access '") ||
          m.contains('is not defined')) {
        return 'Something went wrong on the server. Please try again in a moment.';
      }
    }
    return message;
  }

  @override
  String toString() =>
      'ApiException: $message${statusCode != null ? ' (Status: $statusCode)' : ''}';
}

class PermissionException implements Exception {
  final String message;
  PermissionException(this.message);

  @override
  String toString() => 'PermissionException: $message';
}

class PrintException implements Exception {
  final String message;
  PrintException(this.message);

  @override
  String toString() => 'PrintException: $message';
}

class ShareException implements Exception {
  final String message;
  ShareException(this.message);

  @override
  String toString() => 'ShareException: $message';
}

