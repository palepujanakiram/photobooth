import 'package:dio/dio.dart';

import 'log_truncator.dart';
import 'request_formatter.dart';

const _bytes = LogTruncator(maxLoggedJsonLength: 6000);

/// Lightweight API logging for Flutter **web** when `showGenerationCommentary` is on.
/// Avoids [jsonEncode], pretty-print, and deep sanitization on huge maps (same isolate as UI).
String formatWebApiRequestSummary(RequestOptions options) {
  final buf = StringBuffer();
  buf.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  buf.writeln('📤 API REQUEST (web summary)');
  buf.writeln('${options.method} ${options.uri}');
  final data = options.data;
  if (data == null) {
    buf.writeln('Body: (none)');
  } else if (data is FormData) {
    buf.writeln(
      'Body: FormData (${data.fields.length} fields, ${data.files.length} files)',
    );
  } else if (data is Map) {
    final size = estimatePayloadSizeForLogging(data);
    buf.writeln(
      'Body: map keys [${data.keys.join(', ')}]'
      '${size != null ? ' ~${_bytes.formatBytes(size)}' : ''}',
    );
  } else if (data is List) {
    buf.writeln('Body: list length=${data.length}');
  } else if (data is String) {
    buf.writeln('Body: string length=${data.length}');
  } else {
    buf.writeln('Body: ${data.runtimeType}');
  }
  buf.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  return buf.toString();
}

String formatWebApiResponseSummary(Response<dynamic> response) {
  final startTime =
      response.requestOptions.extra['request_start_time'] as DateTime?;
  final duration =
      startTime != null ? DateTime.now().difference(startTime) : null;

  final buf = StringBuffer();
  buf.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  buf.writeln('📥 API RESPONSE (web summary)');
  buf.writeln('Time: ${DateTime.now().toIso8601String()}');
  if (duration != null) {
    buf.writeln(
      'Duration: ${duration.inMilliseconds}ms (${_bytes.formatDuration(duration)})',
    );
  }
  buf.writeln('${response.requestOptions.method} ${response.requestOptions.uri}');
  buf.writeln('Status: ${response.statusCode}');
  final data = response.data;
  if (data == null) {
    buf.writeln('Body: (null)');
  } else if (data is List) {
    buf.writeln('Body: JSON array length=${data.length}');
  } else if (data is Map) {
    final size = estimatePayloadSizeForLogging(data);
    buf.writeln(
      'Body: JSON object keys [${data.keys.join(', ')}]'
      '${size != null ? ' ~${_bytes.formatBytes(size)}' : ''}',
    );
  } else if (data is String) {
    buf.writeln('Body: text length=${data.length}');
  } else {
    buf.writeln('Body: ${data.runtimeType}');
  }
  buf.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  return buf.toString();
}

String formatWebApiErrorSummary(DioException err) {
  final startTime = err.requestOptions.extra['request_start_time'] as DateTime?;
  final duration =
      startTime != null ? DateTime.now().difference(startTime) : null;

  final buf = StringBuffer();
  buf.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  buf.writeln('❌ API ERROR (web summary)');
  buf.writeln('Time: ${DateTime.now().toIso8601String()}');
  if (duration != null) {
    buf.writeln(
      'Duration: ${duration.inMilliseconds}ms (${_bytes.formatDuration(duration)})',
    );
  }
  buf.writeln('${err.requestOptions.method} ${err.requestOptions.uri}');
  buf.writeln('Type: ${err.type}');
  buf.writeln('Message: ${err.message ?? 'N/A'}');

  final req = err.requestOptions.data;
  if (req is Map) {
    final size = estimatePayloadSizeForLogging(req);
    buf.writeln(
      'Request body: keys [${req.keys.join(', ')}]'
      '${size != null ? ' ~${_bytes.formatBytes(size)}' : ''}',
    );
  } else if (req is FormData) {
    buf.writeln(
      'Request body: FormData (${req.fields.length} fields, ${req.files.length} files)',
    );
  } else if (req != null) {
    buf.writeln('Request body: ${req.runtimeType}');
  }

  final resp = err.response;
  if (resp != null) {
    buf.writeln('Response status: ${resp.statusCode}');
    final data = resp.data;
    if (data is Map) {
      final size = estimatePayloadSizeForLogging(data);
      buf.writeln(
        'Response body: keys [${data.keys.join(', ')}]'
        '${size != null ? ' ~${_bytes.formatBytes(size)}' : ''}',
      );
    } else if (data is List) {
      buf.writeln('Response body: list length=${data.length}');
    } else if (data is String) {
      buf.writeln('Response body: string length=${data.length}');
    } else if (data != null) {
      buf.writeln('Response body: ${data.runtimeType}');
    }
  }

  buf.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  return buf.toString();
}

/// For Bugsnag [extraInfo] on web — never deep-walk huge JSON trees.
Object? webSafeResponseDataSnapshot(dynamic data) {
  if (data == null) return null;
  if (data is Map) {
    final size = estimatePayloadSizeForLogging(data);
    return <String, Object?>{
      'type': 'map',
      'keys': data.keys.map((k) => k.toString()).toList(),
      if (size != null) 'approxBytes': size,
    };
  }
  if (data is List) {
    return <String, Object?>{
      'type': 'list',
      'length': data.length,
    };
  }
  if (data is String) {
    return <String, Object?>{
      'type': 'string',
      'length': data.length,
    };
  }
  return <String, String>{'type': data.runtimeType.toString()};
}
