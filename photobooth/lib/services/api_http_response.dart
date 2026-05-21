import 'package:dio/dio.dart';

import '../utils/exceptions.dart';
import 'api_dio_errors.dart';

/// Parses Dio response body as [Map<String, dynamic>] or throws [ApiException].
Map<String, dynamic> parseJsonMapBody(
  dynamic data, {
  required String unexpectedMessage,
}) {
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return Map<String, dynamic>.from(data);
  throw ApiException(unexpectedMessage);
}

/// Throws [ApiException] when [response] has HTTP status >= 400.
void throwIfHttpErrorResponse(
  Response<dynamic> response, {
  required String operationLabel,
}) {
  final status = response.statusCode;
  if (status == null || status < 400) return;

  final data = response.data;
  if (data is Map) {
    final map = Map<String, dynamic>.from(data);
    throw ApiException(
      map['error']?.toString() ??
          map['message']?.toString() ??
          '$operationLabel ($status)',
      status,
    );
  }
  throw ApiException(
    '$operationLabel ($status): ${data ?? ''}',
    status,
  );
}

/// Web CORS check, then a contextual [ApiException] (share/receipt-style endpoints).
Never throwApiExceptionAfterWebCors(
  DioException dioError, {
  required String messagePrefix,
}) {
  throwIfWebCorsOrNetwork(dioError);
  throw ApiException(
    '$messagePrefix: ${dioError.message}',
    dioError.response?.statusCode,
  );
}
