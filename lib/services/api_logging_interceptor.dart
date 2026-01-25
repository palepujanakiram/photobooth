import 'package:dio/dio.dart';
import 'dart:convert';
import '../utils/constants.dart';
import '../utils/logger.dart';
import 'error_reporting/error_reporting_manager.dart';

/// Interceptor that logs all API requests and responses with detailed timing
/// Logs request method, URL, headers, body, response details, and performance metrics
class ApiLoggingInterceptor extends Interceptor {
  static const int _maxLoggedStringLength = 2000;
  static const int _maxLoggedJsonLength = 6000;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Store request start time for duration calculation
    options.extra['request_start_time'] = DateTime.now();

    if (!AppConstants.kEnableLogOutput) {
      handler.next(options);
      return;
    }
    
    final buffer = StringBuffer();
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('📤 API REQUEST');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('⏱️  Time: ${DateTime.now().toIso8601String()}');
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
    
    // Log request data and size
    if (options.data != null) {
      buffer.writeln('\nRequest Body:');
      
      // Calculate request size
      int requestSize = 0;
      try {
        if (options.data is String) {
          requestSize = (options.data as String).length;
        } else if (options.data is Map || options.data is List) {
          requestSize = jsonEncode(options.data).length;
        }
        if (requestSize > 0) {
          buffer.writeln('📦 Request Size: ${_formatBytes(requestSize)}');
        }
      } catch (_) {
        // Ignore size calculation errors
      }
      
      try {
        if (options.data is FormData) {
          // Handle FormData (multipart)
          final formData = options.data as FormData;
          buffer.writeln('  Type: multipart/form-data');
          if (formData.fields.isNotEmpty) {
            buffer.writeln('  Fields:');
            formData.fields.forEach((field) {
              buffer.writeln('    ${field.key}: ${_sanitizeString(field.value)}');
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
          // Pretty print JSON (sanitized)
          final encoder = JsonEncoder.withIndent('  ');
          final sanitized = _sanitizeData(options.data);
          final jsonString = encoder.convert(sanitized);
          buffer.writeln(_truncateJson(jsonString));
        } else if (options.data is String) {
          // Try to parse as JSON for pretty printing
          try {
            final jsonData = jsonDecode(options.data as String);
            final encoder = JsonEncoder.withIndent('  ');
            final sanitized = _sanitizeData(jsonData);
            buffer.writeln(_truncateJson(encoder.convert(sanitized)));
          } catch (_) {
            // Not JSON, print as-is
            buffer.writeln('  ${_sanitizeString(options.data as String)}');
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
    
    // Track API request in Bugsnag
    ErrorReportingManager.log('API Request: ${options.method} ${options.uri}');
    ErrorReportingManager.setCustomKeys({
      'last_api_method': options.method,
      'last_api_url': options.uri.toString(),
      'last_api_timestamp': DateTime.now().toIso8601String(),
    });
    
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (!AppConstants.kEnableLogOutput) {
      handler.next(response);
      return;
    }

    // Calculate request duration
    final startTime = response.requestOptions.extra['request_start_time'] as DateTime?;
    final duration = startTime != null 
        ? DateTime.now().difference(startTime) 
        : null;
    
    final buffer = StringBuffer();
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('📥 API RESPONSE');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('⏱️  Time: ${DateTime.now().toIso8601String()}');
    if (duration != null) {
      buffer.writeln('⏱️  Duration: ${duration.inMilliseconds}ms (${_formatDuration(duration)})');
    }
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
    
    // Log response data and size
    if (response.data != null) {
      buffer.writeln('\nResponse Body:');
      
      // Calculate response size
      int responseSize = 0;
      try {
        if (response.data is String) {
          responseSize = (response.data as String).length;
        } else if (response.data is List<int>) {
          responseSize = (response.data as List<int>).length;
        } else if (response.data is Map || response.data is List) {
          responseSize = jsonEncode(response.data).length;
        }
        if (responseSize > 0) {
          buffer.writeln('📦 Response Size: ${_formatBytes(responseSize)}');
          
          // Calculate throughput if duration is available
          if (duration != null && duration.inMilliseconds > 0) {
            final throughputKBps = (responseSize / 1024) / (duration.inMilliseconds / 1000);
            buffer.writeln('📊 Throughput: ${throughputKBps.toStringAsFixed(2)} KB/s');
          }
        }
      } catch (_) {
        // Ignore size calculation errors
      }
      
      try {
        if (response.data is List<int>) {
          // Binary data (e.g., image bytes)
          final bytes = response.data as List<int>;
          buffer.writeln('  Type: binary (${_formatBytes(bytes.length)})');
        } else if (response.data is Map || response.data is List) {
          // Pretty print JSON (sanitized)
          final encoder = JsonEncoder.withIndent('  ');
          final sanitized = _sanitizeData(response.data);
          final jsonString = encoder.convert(sanitized);
          buffer.writeln(_truncateJson(jsonString));
        } else if (response.data is String) {
          // Try to parse as JSON for pretty printing
          try {
            final jsonData = jsonDecode(response.data as String);
            final encoder = JsonEncoder.withIndent('  ');
            final sanitized = _sanitizeData(jsonData);
            buffer.writeln(_truncateJson(encoder.convert(sanitized)));
          } catch (_) {
            // Not JSON, print as-is (but limit length)
            final data = _sanitizeString(response.data as String);
            buffer.writeln('  $data');
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
    
    // Track successful API response in Bugsnag with timing
    final durationStr = duration != null ? ' (${duration.inMilliseconds}ms)' : '';
    ErrorReportingManager.log('API Success: ${response.requestOptions.method} ${response.requestOptions.uri} - ${response.statusCode}$durationStr');
    
    // Add detailed performance metrics to Bugsnag
    if (duration != null) {
      ErrorReportingManager.setCustomKeys({
        'last_api_duration_ms': duration.inMilliseconds.toString(),
        'last_api_status': response.statusCode?.toString() ?? 'unknown',
      });
    }
    
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Calculate request duration
    final startTime = err.requestOptions.extra['request_start_time'] as DateTime?;
    final duration = startTime != null 
        ? DateTime.now().difference(startTime) 
        : null;
    
    if (AppConstants.kEnableLogOutput) {
      final buffer = StringBuffer();
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      buffer.writeln('❌ API ERROR');
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      buffer.writeln('⏱️  Time: ${DateTime.now().toIso8601String()}');
      if (duration != null) {
        buffer.writeln('⏱️  Duration: ${duration.inMilliseconds}ms (${_formatDuration(duration)})');
      }
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
                buffer.writeln('    ${field.key}: ${_sanitizeString(field.value)}');
              });
            }
          } else if (err.requestOptions.data is Map || err.requestOptions.data is List) {
            final encoder = JsonEncoder.withIndent('  ');
            final sanitized = _sanitizeData(err.requestOptions.data);
            buffer.writeln(_truncateJson(encoder.convert(sanitized)));
          } else {
            final dataStr = _sanitizeString(err.requestOptions.data.toString());
            buffer.writeln('  $dataStr');
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
              final sanitized = _sanitizeData(err.response!.data);
              buffer.writeln(_truncateJson(encoder.convert(sanitized)));
            } else if (err.response!.data is String) {
              try {
                final jsonData = jsonDecode(err.response!.data as String);
                final encoder = JsonEncoder.withIndent('  ');
                final sanitized = _sanitizeData(jsonData);
                buffer.writeln(_truncateJson(encoder.convert(sanitized)));
              } catch (_) {
                final data = _sanitizeString(err.response!.data as String);
                buffer.writeln('  $data');
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
      
      // Log API failure to Bugsnag with detailed context and timing
      final durationStr = duration != null ? ' (${duration.inMilliseconds}ms)' : '';
      ErrorReportingManager.log('❌ API Error: ${err.requestOptions.method} ${err.requestOptions.uri} - ${err.type}$durationStr');
    }
    
    // Record the error with full context including performance metrics
    ErrorReportingManager.recordError(
      err,
      err.stackTrace,
      reason: 'API Call Failed: ${err.requestOptions.method} ${err.requestOptions.uri}',
      extraInfo: {
        'api_method': err.requestOptions.method,
        'api_url': err.requestOptions.uri.toString(),
        'error_type': err.type.toString(),
        'error_message': err.message ?? 'No message',
        'status_code': err.response?.statusCode?.toString() ?? 'none',
        'status_message': err.response?.statusMessage ?? 'none',
        'response_data': err.response?.data != null
            ? _sanitizeData(err.response?.data)
            : 'none',
        'duration_ms': duration?.inMilliseconds.toString() ?? 'unknown',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    
    handler.next(err);
  }

  /// Masks authorization tokens for security
  String _maskAuthorization(String auth) {
    if (auth.length <= 20) {
      return '***';
    }
    return '${auth.substring(0, 10)}...${auth.substring(auth.length - 4)}';
  }

  /// Sanitizes request/response data to avoid logging huge payloads
  dynamic _sanitizeData(dynamic data) {
    if (data is Map) {
      return data.map((key, value) => MapEntry(key, _sanitizeData(value)));
    }
    if (data is List) {
      return data.map(_sanitizeData).toList();
    }
    if (data is String) {
      return _sanitizeString(data);
    }
    return data;
  }

  /// Redacts or truncates large strings (especially base64 images)
  String _sanitizeString(String value) {
    final lower = value.toLowerCase();
    if (lower.startsWith('data:image') && value.contains('base64,')) {
      return '<base64 image omitted (${_formatBytes(value.length)})>';
    }
    if (value.length > _maxLoggedStringLength) {
      return '${value.substring(0, _maxLoggedStringLength)}... [truncated, ${value.length} chars]';
    }
    return value;
  }

  /// Truncates large JSON payloads for logs
  String _truncateJson(String jsonString) {
    if (jsonString.length > _maxLoggedJsonLength) {
      return '${jsonString.substring(0, _maxLoggedJsonLength)}... [truncated, ${jsonString.length} chars total]';
    }
    return jsonString;
  }

  /// Formats bytes to human-readable format
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  /// Formats duration to human-readable format
  String _formatDuration(Duration duration) {
    if (duration.inSeconds < 1) {
      return '${duration.inMilliseconds}ms';
    } else if (duration.inSeconds < 60) {
      return '${duration.inSeconds}.${(duration.inMilliseconds % 1000).toString().padLeft(3, '0').substring(0, 2)}s';
    } else {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    }
  }
}
