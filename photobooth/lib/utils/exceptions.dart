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

