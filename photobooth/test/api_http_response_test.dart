import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/api_http_response.dart';
import 'package:photobooth/utils/exceptions.dart';

void main() {
  group('parseJsonMapBody', () {
    test('returns Map<String, dynamic> when already typed', () {
      expect(
        parseJsonMapBody({'ok': true}, unexpectedMessage: 'x'),
        {'ok': true},
      );
    });

    test('converts generic Map', () {
      final m = parseJsonMapBody(
        <Object, Object>{'a': 1},
        unexpectedMessage: 'x',
      );
      expect(m['a'], 1);
    });

    test('throws ApiException for non-map', () {
      expect(
        () => parseJsonMapBody('text', unexpectedMessage: 'bad'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('throwIfHttpErrorResponse', () {
    test('no-op for 200', () {
      expect(
        () => throwIfHttpErrorResponse(
          Response(
            requestOptions: RequestOptions(path: '/'),
            statusCode: 200,
            data: {},
          ),
          operationLabel: 'op',
        ),
        returnsNormally,
      );
    });

    test('throws with server message on 400', () {
      expect(
        () => throwIfHttpErrorResponse(
          Response(
            requestOptions: RequestOptions(path: '/'),
            statusCode: 400,
            data: {'message': 'nope'},
          ),
          operationLabel: 'op',
        ),
        throwsA(
          predicate<ApiException>((e) => e.message.contains('nope')),
        ),
      );
    });
  });

  group('throwApiExceptionAfterWebCors', () {
    test('throws ApiException on timeout', () {
      final e = DioException(
        requestOptions: RequestOptions(path: '/'),
        type: DioExceptionType.connectionTimeout,
      );
      expect(
        () => throwApiExceptionAfterWebCors(e, messagePrefix: 'Share'),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
