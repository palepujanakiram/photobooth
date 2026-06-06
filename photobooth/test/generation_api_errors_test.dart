import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/generation_api_errors.dart';
import 'package:photobooth/utils/exceptions.dart';

void main() {
  test('fromDioException parses error and details from JSON body', () {
    final dioError = DioException(
      requestOptions: RequestOptions(path: '/api/generate-image'),
      response: Response(
        requestOptions: RequestOptions(path: '/'),
        statusCode: 422,
        data: {
          'error': 'Generation failed',
          'details': 'face not found',
          'runId': 'run-1',
        },
      ),
    );
    final failure = GenerationApiFailure.fromDioException(dioError);
    expect(failure.userMessage, contains('Generation failed'));
    expect(failure.userMessage, contains('face not found'));
    expect(failure.generationRunId, 'run-1');
  });

  test('rethrowAsApiException throws ApiException', () {
    final failure = GenerationApiFailure(userMessage: 'bad', httpStatusCode: 500);
    expect(
      () => failure.rethrowAsApiException(),
      throwsA(
        predicate<ApiException>((e) => e.statusCode == 500),
      ),
    );
  });

  test('fromDioException handles connection timeout', () {
    final dioError = DioException(
      requestOptions: RequestOptions(path: '/'),
      type: DioExceptionType.connectionTimeout,
    );
    final failure = GenerationApiFailure.fromDioException(dioError);
    expect(failure.userMessage, contains('timed out'));
  });
}
