import 'dart:convert';

import 'package:dio/dio.dart';

import '../../utils/app_strings.dart';
import '../../utils/logger.dart';
import 'body_log_formatting.dart';
import 'log_truncator.dart';
import 'payload_sanitizer.dart';

/// Avoid [jsonEncode] of maps containing a huge `userImageUrl` (logging only).
int? estimatePayloadSizeForLogging(dynamic data) {
  if (data == null) return null;
  if (data is String) return data.length;
  if (data is List<int>) return data.length;
  if (data is Map) {
    final slug = data['userImageUrl'];
    if (slug is String && slug.length > 8192) {
      var total = 64;
      for (final e in data.entries) {
        if (e.key == 'userImageUrl' && e.value is String) {
          total += (e.value as String).length;
        } else {
          try {
            total += jsonEncode({e.key: e.value}).length;
          } catch (_) {
            total += 64;
          }
        }
      }
      return total;
    }
  }
  if (data is Map || data is List) {
    try {
      return jsonEncode(data).length;
    } catch (_) {
      return null;
    }
  }
  return null;
}

class ApiRequestFormatter {
  ApiRequestFormatter(PayloadSanitizer sanitizer, this._truncator)
      : _body = ApiBodyLogFormatting(sanitizer, _truncator);

  final LogTruncator _truncator;
  final ApiBodyLogFormatting _body;

  String format(RequestOptions options) {
    final buffer = StringBuffer();
    buffer.writeln(AppStrings.apiLogSeparator);
    buffer.writeln('📤 API REQUEST');
    buffer.writeln(AppStrings.apiLogSeparator);
    buffer.writeln('⏱️  Time: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Method: ${options.method}');
    buffer.writeln('URL: ${options.uri}');
    _body.appendHeaders(buffer, options.headers);

    if (options.data != null) {
      buffer.writeln('\nRequest Body:');
      try {
        final size = estimatePayloadSizeForLogging(options.data);
        if (size != null) {
          buffer.writeln('📦 Request Size: ${_truncator.formatBytes(size)}');
        }
        _body.appendBody(buffer, options.data);
      } catch (e) {
        buffer.writeln('  [Error formatting request body: $e]');
        buffer.writeln('  ${options.data}');
      }
    }

    buffer.writeln(AppStrings.apiLogSeparator);
    return buffer.toString();
  }
}

class ApiResponseFormatter {
  ApiResponseFormatter(PayloadSanitizer sanitizer, this._truncator)
      : _body = ApiBodyLogFormatting(sanitizer, _truncator);

  final LogTruncator _truncator;
  final ApiBodyLogFormatting _body;

  String format(Response response) {
    final startTime =
        response.requestOptions.extra['request_start_time'] as DateTime?;
    final duration =
        startTime != null ? DateTime.now().difference(startTime) : null;

    final buffer = StringBuffer();
    buffer.writeln(AppStrings.apiLogSeparator);
    buffer.writeln('📥 API RESPONSE');
    buffer.writeln(AppStrings.apiLogSeparator);
    buffer.writeln('⏱️  Time: ${DateTime.now().toIso8601String()}');
    if (duration != null) {
      buffer.writeln(
        '⏱️  Duration: ${duration.inMilliseconds}ms (${_truncator.formatDuration(duration)})',
      );
    }
    buffer.writeln('Method: ${response.requestOptions.method}');
    buffer.writeln('URL: ${response.requestOptions.uri}');
    buffer.writeln('Status Code: ${response.statusCode}');
    buffer.writeln('Status Message: ${response.statusMessage ?? 'N/A'}');
    _body.appendHeaders(
      buffer,
      Map<String, dynamic>.from(
        response.headers.map.map((k, v) => MapEntry(k, v.join(', '))),
      ),
      title: 'Response Headers',
    );

    final data = response.data;
    if (data != null) {
      buffer.writeln('\nResponse Body:');
      try {
        final size = estimatePayloadSizeForLogging(data);
        if (size != null) {
          buffer.writeln('📦 Response Size: ${_truncator.formatBytes(size)}');
          if (duration != null && duration.inMilliseconds > 0) {
            final throughputKBps =
                (size / 1024) / (duration.inMilliseconds / 1000);
            buffer.writeln(
              '📊 Throughput: ${throughputKBps.toStringAsFixed(2)} KB/s',
            );
          }
        }
        _body.appendBody(buffer, data);
      } catch (e) {
        buffer.writeln('  [Error formatting response body: $e]');
      }
    }

    buffer.writeln(AppStrings.apiLogSeparator);
    return buffer.toString();
  }

  String formatError(DioException err) {
    final startTime =
        err.requestOptions.extra['request_start_time'] as DateTime?;
    final duration =
        startTime != null ? DateTime.now().difference(startTime) : null;

    final buffer = StringBuffer();
    buffer.writeln(AppStrings.apiLogSeparator);
    buffer.writeln('❌ API ERROR');
    buffer.writeln(AppStrings.apiLogSeparator);
    buffer.writeln('⏱️  Time: ${DateTime.now().toIso8601String()}');
    if (duration != null) {
      buffer.writeln(
        '⏱️  Duration: ${duration.inMilliseconds}ms (${_truncator.formatDuration(duration)})',
      );
    }
    buffer.writeln('Method: ${err.requestOptions.method}');
    buffer.writeln('URL: ${err.requestOptions.uri}');
    buffer.writeln('Error Type: ${err.type}');
    buffer.writeln('Error Message: ${err.message ?? 'N/A'}');
    _body.appendHeaders(buffer, err.requestOptions.headers, title: 'Request Headers');

    if (err.requestOptions.data != null) {
      buffer.writeln('\nRequest Body:');
      try {
        _body.appendBody(buffer, err.requestOptions.data);
      } catch (e) {
        buffer.writeln('  [Error formatting: $e]');
      }
    }

    final resp = err.response;
    if (resp != null) {
      buffer.writeln('\nResponse Status Code: ${resp.statusCode}');
      buffer.writeln('Response Status Message: ${resp.statusMessage ?? 'N/A'}');
      _body.appendHeaders(
        buffer,
        Map<String, dynamic>.from(
          resp.headers.map.map((k, v) => MapEntry(k, v.join(', '))),
        ),
        title: 'Response Headers',
      );
      if (resp.data != null) {
        buffer.writeln('\nResponse Body:');
        try {
          _body.appendBody(buffer, resp.data);
        } catch (e) {
          buffer.writeln('  [Error formatting response: $e]');
        }
      }
    }

    buffer.writeln(AppStrings.apiLogSeparator);
    return buffer.toString();
  }
}

void debugApiLog(String message) {
  AppLogger.debug(message);
}
