import 'package:dio/dio.dart';
import 'dart:convert';
import '../utils/logger.dart';

/// Interceptor that logs all API requests and responses
/// Logs request method, URL, headers, body, and response details
class ApiLoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final buffer = StringBuffer();
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('📤 API REQUEST');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('Method: ${options.method}');
    buffer.writeln('URL: ${options.uri}');
    
    // Log headers (mask sensitive information)
    if (options.headers.isNotEmpty) {
      buffer.writeln('\nHeaders:');
      options.headers.forEach((key, value) {
        // Mask authorization tokens
        if (key.toLowerCase() == 'authorization' && value is String) {
          final masked = _maskAuthorization(value);
          buffer.writeln('  $key: $masked');
        } else {
          buffer.writeln('  $key: $value');
        }
      });
    }
    
    // Log request data
    if (options.data != null) {
      buffer.writeln('\nRequest Body:');
      try {
        if (options.data is FormData) {
          // Handle FormData (multipart)
          final formData = options.data as FormData;
          buffer.writeln('  Type: multipart/form-data');
          if (formData.fields.isNotEmpty) {
            buffer.writeln('  Fields:');
            formData.fields.forEach((field) {
              buffer.writeln('    ${field.key}: ${field.value}');
            });
          }
          if (formData.files.isNotEmpty) {
            buffer.writeln('  Files:');
            formData.files.forEach((file) {
              final fileName = file.value.filename ?? 'unknown';
              final fileSize = file.value.length;
              buffer.writeln('    ${file.key}: $fileName (${_formatBytes(fileSize)})');
            });
          }
        } else if (options.data is Map || options.data is List) {
          // Pretty print JSON
          final encoder = JsonEncoder.withIndent('  ');
          final jsonString = encoder.convert(options.data);
          buffer.writeln(jsonString);
        } else if (options.data is String) {
          // Try to parse as JSON for pretty printing
          try {
            final jsonData = jsonDecode(options.data as String);
            final encoder = JsonEncoder.withIndent('  ');
            buffer.writeln(encoder.convert(jsonData));
          } catch (_) {
            // Not JSON, print as-is
            buffer.writeln('  ${options.data}');
          }
        } else {
          buffer.writeln('  ${options.data}');
        }
      } catch (e) {
        buffer.writeln('  [Error formatting request body: $e]');
        buffer.writeln('  ${options.data}');
      }
    }
    
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    AppLogger.debug(buffer.toString());
    
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final buffer = StringBuffer();
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('📥 API RESPONSE');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('Method: ${response.requestOptions.method}');
    buffer.writeln('URL: ${response.requestOptions.uri}');
    buffer.writeln('Status Code: ${response.statusCode}');
    buffer.writeln('Status Message: ${response.statusMessage ?? 'N/A'}');
    
    // Log response headers
    if (response.headers.map.isNotEmpty) {
      buffer.writeln('\nResponse Headers:');
      response.headers.map.forEach((key, values) {
        buffer.writeln('  $key: ${values.join(', ')}');
      });
    }
    
    // Log response data
    if (response.data != null) {
      buffer.writeln('\nResponse Body:');
      try {
        if (response.data is List<int>) {
          // Binary data (e.g., image bytes)
          final bytes = response.data as List<int>;
          buffer.writeln('  Type: binary (${_formatBytes(bytes.length)})');
        } else if (response.data is Map || response.data is List) {
          // Pretty print JSON
          final encoder = JsonEncoder.withIndent('  ');
          final jsonString = encoder.convert(response.data);
          buffer.writeln(jsonString);
        } else if (response.data is String) {
          // Try to parse as JSON for pretty printing
          try {
            final jsonData = jsonDecode(response.data as String);
            final encoder = JsonEncoder.withIndent('  ');
            buffer.writeln(encoder.convert(jsonData));
          } catch (_) {
            // Not JSON, print as-is (but limit length)
            final data = response.data as String;
            if (data.length > 1000) {
              buffer.writeln('  ${data.substring(0, 1000)}... [truncated, ${data.length} chars total]');
            } else {
              buffer.writeln('  $data');
            }
          }
        } else {
          final dataStr = response.data.toString();
          if (dataStr.length > 1000) {
            buffer.writeln('  ${dataStr.substring(0, 1000)}... [truncated]');
          } else {
            buffer.writeln('  $dataStr');
          }
        }
      } catch (e) {
        buffer.writeln('  [Error formatting response body: $e]');
        final dataStr = response.data.toString();
        if (dataStr.length > 500) {
          buffer.writeln('  ${dataStr.substring(0, 500)}... [truncated]');
        } else {
          buffer.writeln('  $dataStr');
        }
      }
    }
    
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    AppLogger.debug(buffer.toString());
    
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final buffer = StringBuffer();
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('❌ API ERROR');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('Method: ${err.requestOptions.method}');
    buffer.writeln('URL: ${err.requestOptions.uri}');
    buffer.writeln('Error Type: ${err.type}');
    buffer.writeln('Error Message: ${err.message ?? 'N/A'}');
    
    // Log request details
    if (err.requestOptions.headers.isNotEmpty) {
      buffer.writeln('\nRequest Headers:');
      err.requestOptions.headers.forEach((key, value) {
        if (key.toLowerCase() == 'authorization' && value is String) {
          final masked = _maskAuthorization(value);
          buffer.writeln('  $key: $masked');
        } else {
          buffer.writeln('  $key: $value');
        }
      });
    }
    
    if (err.requestOptions.data != null) {
      buffer.writeln('\nRequest Body:');
      try {
        if (err.requestOptions.data is FormData) {
          final formData = err.requestOptions.data as FormData;
          buffer.writeln('  Type: multipart/form-data');
          if (formData.fields.isNotEmpty) {
            buffer.writeln('  Fields:');
            formData.fields.forEach((field) {
              buffer.writeln('    ${field.key}: ${field.value}');
            });
          }
        } else if (err.requestOptions.data is Map || err.requestOptions.data is List) {
          final encoder = JsonEncoder.withIndent('  ');
          buffer.writeln(encoder.convert(err.requestOptions.data));
        } else {
          final dataStr = err.requestOptions.data.toString();
          if (dataStr.length > 500) {
            buffer.writeln('  ${dataStr.substring(0, 500)}... [truncated]');
          } else {
            buffer.writeln('  $dataStr');
          }
        }
      } catch (e) {
        buffer.writeln('  [Error formatting: $e]');
      }
    }
    
    // Log response details if available
    if (err.response != null) {
      buffer.writeln('\nResponse Status Code: ${err.response?.statusCode}');
      buffer.writeln('Response Status Message: ${err.response?.statusMessage ?? 'N/A'}');
      
      if (err.response?.headers.map.isNotEmpty ?? false) {
        buffer.writeln('\nResponse Headers:');
        err.response!.headers.map.forEach((key, values) {
          buffer.writeln('  $key: ${values.join(', ')}');
        });
      }
      
      if (err.response?.data != null) {
        buffer.writeln('\nResponse Body:');
        try {
          if (err.response!.data is Map || err.response!.data is List) {
            final encoder = JsonEncoder.withIndent('  ');
            buffer.writeln(encoder.convert(err.response!.data));
          } else if (err.response!.data is String) {
            try {
              final jsonData = jsonDecode(err.response!.data as String);
              final encoder = JsonEncoder.withIndent('  ');
              buffer.writeln(encoder.convert(jsonData));
            } catch (_) {
              final data = err.response!.data as String;
              if (data.length > 1000) {
                buffer.writeln('  ${data.substring(0, 1000)}... [truncated]');
              } else {
                buffer.writeln('  $data');
              }
            }
          } else {
            final dataStr = err.response!.data.toString();
            if (dataStr.length > 1000) {
              buffer.writeln('  ${dataStr.substring(0, 1000)}... [truncated]');
            } else {
              buffer.writeln('  $dataStr');
            }
          }
        } catch (e) {
          buffer.writeln('  [Error formatting response: $e]');
        }
      }
    }
    
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    AppLogger.error(buffer.toString(), error: err);
    
    handler.next(err);
  }

  /// Masks authorization tokens for security
  String _maskAuthorization(String auth) {
    if (auth.length <= 20) {
      return '***';
    }
    return '${auth.substring(0, 10)}...${auth.substring(auth.length - 4)}';
  }

  /// Formats bytes to human-readable format
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
