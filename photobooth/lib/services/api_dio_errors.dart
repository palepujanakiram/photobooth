import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../utils/app_strings.dart';
import '../utils/constants.dart';
import '../utils/exceptions.dart';

/// Throws [ApiException] when a web [DioException] looks like CORS or offline fetch.
///
/// No-op on mobile/desktop. Call before mapping other Dio errors so web users get
/// an actionable message.
void throwIfWebCorsOrNetwork(DioException dioError) {
  if (!kIsWeb) return;
  if (dioError.type != DioExceptionType.connectionError &&
      dioError.type != DioExceptionType.unknown) {
    return;
  }
  final errorMessage = dioError.message ?? '';
  final looksLikeCorsOrOffline = errorMessage.contains('XMLHttpRequest') ||
      errorMessage.contains('CORS') ||
      errorMessage.contains(AppStrings.failedToFetch) ||
      errorMessage.contains('NetworkError') ||
      errorMessage.contains('connection errored');
  if (!looksLikeCorsOrOffline) return;

  throw ApiException(
    'CORS/Network Error: The API server at ${AppConstants.kBaseUrl} may not be configured to allow requests from this origin (${kIsWeb ? "web browser" : "app"}). '
    'This is typically a CORS (Cross-Origin Resource Sharing) issue. '
    'Please ensure the server allows requests from your domain, or contact the server administrator. '
    'Error: ${dioError.message ?? AppStrings.unknownNetworkError}',
  );
}

/// True for timeouts and transport-level connection failures.
bool isDioTimeoutOrConnection(DioException dioError) {
  return dioError.type == DioExceptionType.connectionTimeout ||
      dioError.type == DioExceptionType.receiveTimeout ||
      dioError.type == DioExceptionType.sendTimeout ||
      dioError.type == DioExceptionType.connectionError;
}

/// Builds a human-readable message from [dioError.response] when present.
String buildMessageFromDioResponse(DioException dioError) {
  if (dioError.response == null) {
    return '${AppConstants.kErrorApiCall}: ${dioError.message}';
  }
  final responseBody = dioError.response?.data;
  if (responseBody is Map<String, dynamic>) {
    return responseBody['message'] as String? ??
        responseBody['error'] as String? ??
        'API Error: ${dioError.response?.statusCode}';
  }
  if (responseBody is String) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map) {
        return decoded['message'] as String? ??
            decoded['error'] as String? ??
            responseBody;
      }
    } catch (_) {
      return responseBody;
    }
    return responseBody;
  }
  return 'API Error: ${dioError.response?.statusCode} - ${dioError.message}';
}

/// Standard mapping used by most [ApiService] methods (always throws).
Never throwMappedApiException(DioException dioError) {
  throwIfWebCorsOrNetwork(dioError);
  if (isDioTimeoutOrConnection(dioError)) {
    throw ApiException(AppConstants.kErrorNetwork);
  }
  throw ApiException(
    buildMessageFromDioResponse(dioError),
    dioError.response?.statusCode,
  );
}
