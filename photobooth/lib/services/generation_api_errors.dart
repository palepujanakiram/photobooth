import 'package:dio/dio.dart';

import '../utils/constants.dart';
import '../utils/exceptions.dart';
import '../utils/logger.dart';
import 'api_dio_errors.dart';

/// Parsed error from POST `/api/generate-image` (and retry loop) responses.
///
/// Server may return `{ "error", "details", "runId" }` per the generation API spec.
class GenerationApiFailure {
  const GenerationApiFailure({
    required this.userMessage,
    this.httpStatusCode,
    this.generationRunId,
  });

  final String userMessage;
  final int? httpStatusCode;

  /// Optional run id returned by the API for support / Bugsnag correlation.
  final String? generationRunId;

  /// Converts [dioError] after retries are exhausted (or for non-retryable errors).
  static GenerationApiFailure fromDioException(DioException dioError) {
    throwIfWebCorsOrNetwork(dioError);

    final requestTimedOut = isDioTimeoutOrConnection(dioError) ||
        dioError.type == DioExceptionType.sendTimeout;

    if (dioError.response == null) {
      final message = requestTimedOut
          ? 'Request timed out. Please try again.'
          : '${AppConstants.kErrorNetwork}: ${dioError.message}';
      return GenerationApiFailure(userMessage: message);
    }

    final httpStatusCode = dioError.response?.statusCode;
    final responseBody = dioError.response?.data;

    if (responseBody is Map<String, dynamic>) {
      var userMessage = responseBody['error'] as String? ??
          responseBody['message'] as String? ??
          'API Error: $httpStatusCode';
      final detailText = responseBody['details'] as String?;
      final runId = responseBody['runId'] as String?;
      if (detailText != null &&
          detailText.isNotEmpty &&
          detailText.trim() != userMessage.trim()) {
        userMessage = '$userMessage: $detailText';
      }
      if (runId != null) {
        AppLogger.debug('❌ Generation failed (Run ID: $runId): $userMessage');
      }
      return GenerationApiFailure(
        userMessage: userMessage,
        httpStatusCode: httpStatusCode,
        generationRunId: runId,
      );
    }

    if (responseBody is String) {
      return GenerationApiFailure(
        userMessage: responseBody,
        httpStatusCode: httpStatusCode,
      );
    }

    final message = requestTimedOut
        ? 'Request timed out. Please try again.'
        : 'API Error: $httpStatusCode - ${dioError.message}';
    return GenerationApiFailure(
      userMessage: message,
      httpStatusCode: httpStatusCode,
    );
  }

  /// Throws [ApiException] for the UI layer (same shape as before refactor).
  Never rethrowAsApiException() {
    throw ApiException(userMessage, httpStatusCode);
  }
}
