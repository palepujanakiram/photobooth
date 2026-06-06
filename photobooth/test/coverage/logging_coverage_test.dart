import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/api_logging/body_log_formatting.dart';
import 'package:photobooth/services/api_logging/log_truncator.dart';
import 'package:photobooth/services/api_logging/payload_sanitizer.dart';
import 'package:photobooth/services/api_logging/request_formatter.dart';
import 'package:photobooth/services/api_logging/web_api_log_summary.dart';

void main() {
  const truncator = LogTruncator(maxLoggedJsonLength: 200);
  const sanitizer = PayloadSanitizer();
  final bodyFmt = ApiBodyLogFormatting(sanitizer, truncator);
  final reqFmt = ApiRequestFormatter(sanitizer, truncator);
  final resFmt = ApiResponseFormatter(sanitizer, truncator);

  test('estimatePayloadSizeForLogging branches', () {
    expect(estimatePayloadSizeForLogging(null), isNull);
    expect(estimatePayloadSizeForLogging('abc'), 3);
    expect(estimatePayloadSizeForLogging(<int>[1, 2]), 2);
    expect(
      estimatePayloadSizeForLogging({
        'userImageUrl': 'x' * 9000,
        'a': 1,
      }),
      isNotNull,
    );
    expect(estimatePayloadSizeForLogging({'a': 1}), greaterThan(0));
    expect(estimatePayloadSizeForLogging([1, 2]), greaterThan(0));
    expect(estimatePayloadSizeForLogging(Object()), isNull);
  });

  test('ApiRequestFormatter formats request with map and error path', () {
    final s = reqFmt.format(
      RequestOptions(
        path: '/api/x',
        method: 'POST',
        headers: {'Authorization': 'Bearer secret-token-abcdefghijklmnop'},
        data: {'key': 'value', 'userImageUrl': 'data:image/jpeg;base64,${'a' * 9000}'},
      ),
    );
    expect(s, contains('POST'));
    expect(s, contains('Request Body'));

    final bad = reqFmt.format(
      RequestOptions(
        path: '/x',
        method: 'GET',
        data: {Object(): Object()},
      ),
    );
    expect(bad, contains('Request Body'));
  });

  test('ApiResponseFormatter formats response and error', () {
    final start = DateTime.now().subtract(const Duration(milliseconds: 5));
    final resp = Response(
      requestOptions: RequestOptions(
        path: '/api/x',
        method: 'GET',
        extra: {'request_start_time': start},
      ),
      statusCode: 200,
      statusMessage: 'OK',
      headers: Headers.fromMap({
        'content-type': ['application/json'],
      }),
      data: {'ok': true},
    );
    final formatted = resFmt.format(resp);
    expect(formatted, contains('200'));
    expect(formatted, contains('Throughput'));

    final err = resFmt.formatError(
      DioException(
        requestOptions: RequestOptions(
          path: '/api/x',
          method: 'POST',
          data: 'plain',
          extra: {'request_start_time': start},
        ),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/api/x'),
          statusCode: 400,
          data: {'error': 'bad'},
        ),
      ),
    );
    expect(err, contains('API ERROR'));
  });

  test('ApiBodyLogFormatting appendBody variants', () {
    final buf = StringBuffer();
    final form = FormData.fromMap({
      'f': 'v',
      'file': MultipartFile.fromBytes([1, 2, 3], filename: 'a.jpg'),
    });
    bodyFmt.appendBody(buf, form);
    expect(buf.toString(), contains('multipart'));

    final buf2 = StringBuffer();
    bodyFmt.appendBody(buf2, {'a': 1});
    expect(buf2.toString(), isNotEmpty);

    final buf3 = StringBuffer();
    bodyFmt.appendBody(buf3, '{"x":1}');
    expect(buf3.toString(), isNotEmpty);

    final buf4 = StringBuffer();
    bodyFmt.appendBody(buf4, Uint8List.fromList(List<int>.generate(1200, (i) => i % 256)));
    expect(buf4.toString(), contains('truncated'));

    final buf5 = StringBuffer();
    bodyFmt.appendBody(buf5, _ThrowOnFormat());
    expect(buf5.toString(), contains('truncated'));

    final buf6 = StringBuffer();
    bodyFmt.appendHeaders(buf6, {'Authorization': 'Bearer x'});
    expect(buf6.toString(), contains('Authorization'));
  });

  test('PayloadSanitizer nested map and prettyJson', () {
    expect(
      sanitizer.sanitizeData({'nested': {'password': 'x'}}),
      isNotNull,
    );
    expect(sanitizer.prettyJson({'a': 1}), contains('"a"'));
  });

  test('LogTruncator duration branches', () {
    expect(truncator.formatDuration(const Duration(seconds: 90)), contains('m'));
    expect(truncator.formatDuration(const Duration(seconds: 5)), contains('.'));
  });

  test('web api log summary error path', () {
    final s = formatWebApiErrorSummary(
      DioException(
        requestOptions: RequestOptions(path: '/x', method: 'GET'),
        type: DioExceptionType.connectionError,
      ),
    );
    expect(s, contains('ERROR'));
  });

  test('formatWebApiRequestSummary form data', () {
    final s = formatWebApiRequestSummary(
      RequestOptions(
        path: '/x',
        method: 'POST',
        data: FormData.fromMap({'a': 'b'}),
      ),
    );
    expect(s, contains('FormData'));
  });
}

class _ThrowOnFormat {
  @override
  String toString() => 'x' * 2000;
}
