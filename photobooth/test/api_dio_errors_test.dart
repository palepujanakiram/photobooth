import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/api_dio_errors.dart';
import 'package:photobooth/utils/exceptions.dart';

void main() {
  test('isDioTimeoutOrConnection detects connection errors', () {
    final dioError = DioException(
      requestOptions: RequestOptions(path: '/'),
      type: DioExceptionType.connectionTimeout,
    );
    expect(isDioTimeoutOrConnection(dioError), isTrue);
  });

  test('buildMessageFromDioResponse uses response body when present', () {
    final dioError = DioException(
      requestOptions: RequestOptions(path: '/'),
      response: Response(
        requestOptions: RequestOptions(path: '/'),
        statusCode: 400,
        data: {'message': 'bad request'},
      ),
    );
    expect(buildMessageFromDioResponse(dioError), 'bad request');
  });

  test('throwMappedApiException throws ApiException', () {
    final dioError = DioException(
      requestOptions: RequestOptions(path: '/'),
      type: DioExceptionType.connectionTimeout,
    );
    expect(
      () => throwMappedApiException(dioError),
      throwsA(isA<ApiException>()),
    );
  });
}
