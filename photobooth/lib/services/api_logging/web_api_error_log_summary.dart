import 'package:dio/dio.dart';

import 'log_truncator.dart';
import 'payload_size_estimate.dart';

void appendWebApiErrorRequestBody(
  StringBuffer buf,
  dynamic req,
  LogTruncator bytes,
) {
  if (req is Map) {
    final size = estimatePayloadSizeForLogging(req);
    buf.writeln(
      'Request body: keys [${req.keys.join(', ')}]'
      '${size != null ? ' ~${bytes.formatBytes(size)}' : ''}',
    );
    return;
  }
  if (req is FormData) {
    buf.writeln(
      'Request body: FormData (${req.fields.length} fields, ${req.files.length} files)',
    );
    return;
  }
  if (req != null) {
    buf.writeln('Request body: ${req.runtimeType}');
  }
}

void appendWebApiErrorResponseBody(
  StringBuffer buf,
  Response<dynamic>? resp,
  LogTruncator bytes,
) {
  if (resp == null) return;
  buf.writeln('Response status: ${resp.statusCode}');
  final data = resp.data;
  if (data is Map) {
    final size = estimatePayloadSizeForLogging(data);
    buf.writeln(
      'Response body: keys [${data.keys.join(', ')}]'
      '${size != null ? ' ~${bytes.formatBytes(size)}' : ''}',
    );
    return;
  }
  if (data is List) {
    buf.writeln('Response body: list length=${data.length}');
    return;
  }
  if (data is String) {
    buf.writeln('Response body: string length=${data.length}');
    return;
  }
  if (data != null) {
    buf.writeln('Response body: ${data.runtimeType}');
  }
}
