import 'dart:convert';

import 'package:dio/dio.dart';

import 'log_truncator.dart';
import 'payload_sanitizer.dart';

/// Shared request/response body formatting for API debug logs (mobile formatter).
class ApiBodyLogFormatting {
  const ApiBodyLogFormatting(this._sanitizer, this._truncator);

  final PayloadSanitizer _sanitizer;
  final LogTruncator _truncator;

  void appendBody(
    StringBuffer buffer,
    dynamic data, {
    String indent = '  ',
  }) {
    if (data is FormData) {
      buffer.writeln('${indent}Type: multipart/form-data');
      if (data.fields.isNotEmpty) {
        buffer.writeln('${indent}Fields:');
        for (final field in data.fields) {
          buffer.writeln(
            '$indent  ${field.key}: ${_sanitizer.sanitizeString(field.value)}',
          );
        }
      }
      if (data.files.isNotEmpty) {
        buffer.writeln('${indent}Files:');
        for (final file in data.files) {
          final fileName = file.value.filename ?? 'unknown';
          final fileSize = file.value.length;
          buffer.writeln(
            '$indent  ${file.key}: $fileName (${_truncator.formatBytes(fileSize)})',
          );
        }
      }
      return;
    }
    if (data is Map || data is List) {
      buffer.writeln(_truncator.truncateJson(_sanitizer.prettyJson(data)));
      return;
    }
    if (data is String) {
      try {
        final jsonData = jsonDecode(data);
        buffer.writeln(
          _truncator.truncateJson(_sanitizer.prettyJson(jsonData)),
        );
      } catch (_) {
        buffer.writeln('$indent${_sanitizer.sanitizeString(data)}');
      }
      return;
    }
    if (data is List<int>) {
      buffer.writeln(
        '${indent}Type: binary (${_truncator.formatBytes(data.length)})',
      );
      return;
    }
    final str = data.toString();
    buffer.writeln(
      str.length > 1000 ? '${str.substring(0, 1000)}... [truncated]' : str,
    );
  }

  void appendHeaders(
    StringBuffer buffer,
    Map<String, dynamic> headers, {
    String title = 'Headers',
  }) {
    if (headers.isEmpty) return;
    buffer.writeln('\n$title:');
    headers.forEach((key, value) {
      if (key.toLowerCase() == 'authorization' && value is String) {
        buffer.writeln('  $key: ${_sanitizer.maskAuthorization(value)}');
      } else {
        buffer.writeln('  $key: $value');
      }
    });
  }
}
