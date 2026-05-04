import 'dart:convert';

import 'package:dio/dio.dart';

import '../../utils/logger.dart';
import 'log_truncator.dart';
import 'payload_sanitizer.dart';

class ApiRequestFormatter {
  const ApiRequestFormatter(this._sanitizer, this._truncator);

  final PayloadSanitizer _sanitizer;
  final LogTruncator _truncator;

  String format(RequestOptions options) {
    final buffer = StringBuffer();
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('📤 API REQUEST');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('⏱️  Time: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Method: ${options.method}');
    buffer.writeln('URL: ${options.uri}');

    if (options.headers.isNotEmpty) {
      buffer.writeln('\nHeaders:');
      options.headers.forEach((key, value) {
        if (key.toLowerCase() == 'authorization' && value is String) {
          buffer.writeln('  $key: ${_sanitizer.maskAuthorization(value)}');
        } else {
          buffer.writeln('  $key: $value');
        }
      });
    }

    if (options.data != null) {
      buffer.writeln('\nRequest Body:');

      try {
        final size = _estimateSize(options.data);
        if (size != null) {
          buffer.writeln('📦 Request Size: ${_truncator.formatBytes(size)}');
        }
      } catch (_) {
        // Best-effort
      }

      try {
        final data = options.data;
        if (data is FormData) {
          buffer.writeln('  Type: multipart/form-data');
          if (data.fields.isNotEmpty) {
            buffer.writeln('  Fields:');
            for (final field in data.fields) {
              buffer.writeln(
                '    ${field.key}: ${_sanitizer.sanitizeString(field.value)}',
              );
            }
          }
          if (data.files.isNotEmpty) {
            buffer.writeln('  Files:');
            for (final file in data.files) {
              final fileName = file.value.filename ?? 'unknown';
              final fileSize = file.value.length;
              buffer.writeln(
                '    ${file.key}: $fileName (${_truncator.formatBytes(fileSize)})',
              );
            }
          }
        } else if (data is Map || data is List) {
          buffer.writeln(_truncator.truncateJson(_sanitizer.prettyJson(data)));
        } else if (data is String) {
          try {
            final jsonData = jsonDecode(data);
            buffer.writeln(
              _truncator.truncateJson(_sanitizer.prettyJson(jsonData)),
            );
          } catch (_) {
            buffer.writeln('  ${_sanitizer.sanitizeString(data)}');
          }
        } else {
          buffer.writeln('  $data');
        }
      } catch (e) {
        buffer.writeln('  [Error formatting request body: $e]');
        buffer.writeln('  ${options.data}');
      }
    }

    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    return buffer.toString();
  }

  int? _estimateSize(dynamic data) {
    if (data == null) return null;
    if (data is String) return data.length;
    if (data is List<int>) return data.length;
    if (data is Map || data is List) return jsonEncode(data).length;
    return null;
  }
}

class ApiResponseFormatter {
  const ApiResponseFormatter(this._sanitizer, this._truncator);

  final PayloadSanitizer _sanitizer;
  final LogTruncator _truncator;

  String format(Response response) {
    final startTime =
        response.requestOptions.extra['request_start_time'] as DateTime?;
    final duration =
        startTime != null ? DateTime.now().difference(startTime) : null;

    final buffer = StringBuffer();
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('📥 API RESPONSE');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
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

    if (response.headers.map.isNotEmpty) {
      buffer.writeln('\nResponse Headers:');
      for (final entry in response.headers.map.entries) {
        buffer.writeln('  ${entry.key}: ${entry.value.join(', ')}');
      }
    }

    final data = response.data;
    if (data != null) {
      buffer.writeln('\nResponse Body:');
      try {
        final size = _estimateSize(data);
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
      } catch (_) {}

      try {
        if (data is List<int>) {
          buffer.writeln('  Type: binary (${_truncator.formatBytes(data.length)})');
        } else if (data is Map || data is List) {
          buffer.writeln(_truncator.truncateJson(_sanitizer.prettyJson(data)));
        } else if (data is String) {
          try {
            final jsonData = jsonDecode(data);
            buffer.writeln(
              _truncator.truncateJson(_sanitizer.prettyJson(jsonData)),
            );
          } catch (_) {
            buffer.writeln('  ${_sanitizer.sanitizeString(data)}');
          }
        } else {
          final str = data.toString();
          buffer.writeln(
            str.length > 1000 ? '${str.substring(0, 1000)}... [truncated]' : str,
          );
        }
      } catch (e) {
        buffer.writeln('  [Error formatting response body: $e]');
      }
    }

    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    return buffer.toString();
  }

  String formatError(DioException err) {
    final startTime =
        err.requestOptions.extra['request_start_time'] as DateTime?;
    final duration =
        startTime != null ? DateTime.now().difference(startTime) : null;

    final buffer = StringBuffer();
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('❌ API ERROR');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
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

    if (err.requestOptions.headers.isNotEmpty) {
      buffer.writeln('\nRequest Headers:');
      err.requestOptions.headers.forEach((key, value) {
        if (key.toLowerCase() == 'authorization' && value is String) {
          buffer.writeln('  $key: ${_sanitizer.maskAuthorization(value)}');
        } else {
          buffer.writeln('  $key: $value');
        }
      });
    }

    if (err.requestOptions.data != null) {
      buffer.writeln('\nRequest Body:');
      try {
        final data = err.requestOptions.data;
        if (data is FormData) {
          buffer.writeln('  Type: multipart/form-data');
          if (data.fields.isNotEmpty) {
            buffer.writeln('  Fields:');
            for (final field in data.fields) {
              buffer.writeln(
                '    ${field.key}: ${_sanitizer.sanitizeString(field.value)}',
              );
            }
          }
        } else if (data is Map || data is List) {
          buffer.writeln(_truncator.truncateJson(_sanitizer.prettyJson(data)));
        } else {
          buffer.writeln('  ${_sanitizer.sanitizeString(data.toString())}');
        }
      } catch (e) {
        buffer.writeln('  [Error formatting: $e]');
      }
    }

    final resp = err.response;
    if (resp != null) {
      buffer.writeln('\nResponse Status Code: ${resp.statusCode}');
      buffer.writeln('Response Status Message: ${resp.statusMessage ?? 'N/A'}');
      if (resp.headers.map.isNotEmpty) {
        buffer.writeln('\nResponse Headers:');
        for (final entry in resp.headers.map.entries) {
          buffer.writeln('  ${entry.key}: ${entry.value.join(', ')}');
        }
      }
      final data = resp.data;
      if (data != null) {
        buffer.writeln('\nResponse Body:');
        try {
          if (data is Map || data is List) {
            buffer.writeln(_truncator.truncateJson(_sanitizer.prettyJson(data)));
          } else if (data is String) {
            buffer.writeln('  ${_sanitizer.sanitizeString(data)}');
          } else {
            final str = data.toString();
            buffer.writeln(
              str.length > 1000 ? '${str.substring(0, 1000)}... [truncated]' : str,
            );
          }
        } catch (e) {
          buffer.writeln('  [Error formatting response: $e]');
        }
      }
    }

    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    return buffer.toString();
  }

  int? _estimateSize(dynamic data) {
    if (data == null) return null;
    if (data is String) return data.length;
    if (data is List<int>) return data.length;
    if (data is Map || data is List) return jsonEncode(data).length;
    return null;
  }
}

void debugApiLog(String message) {
  AppLogger.debug(message);
}

