import 'package:dio/dio.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';
import 'error_reporting/error_reporting_manager.dart';
import 'api_logging/log_truncator.dart';
import 'api_logging/payload_sanitizer.dart';
import 'api_logging/request_formatter.dart';

/// Interceptor that logs all API requests and responses with detailed timing
/// Logs request method, URL, headers, body, response details, and performance metrics
class ApiLoggingInterceptor extends Interceptor {
  static const _sanitizer = PayloadSanitizer(maxLoggedStringLength: 2000);
  static const _truncator = LogTruncator(maxLoggedJsonLength: 6000);
  static const _requestFormatter = ApiRequestFormatter(_sanitizer, _truncator);
  static const _responseFormatter = ApiResponseFormatter(_sanitizer, _truncator);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Store request start time for duration calculation
    options.extra['request_start_time'] = DateTime.now();

    if (!AppConstants.kEnableLogOutput) {
      handler.next(options);
      return;
    }

    AppLogger.debug(_requestFormatter.format(options));
    
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

    AppLogger.debug(_responseFormatter.format(response));
    
    // Track successful API response in Bugsnag with timing
    final startTime =
        response.requestOptions.extra['request_start_time'] as DateTime?;
    final duration =
        startTime != null ? DateTime.now().difference(startTime) : null;
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
    final startTime = err.requestOptions.extra['request_start_time'] as DateTime?;
    final duration = startTime != null 
        ? DateTime.now().difference(startTime) 
        : null;
    
    if (AppConstants.kEnableLogOutput) {
      AppLogger.error(_responseFormatter.formatError(err), error: err);
      
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
            ? _sanitizer.sanitizeData(err.response?.data)
            : 'none',
        'duration_ms': duration?.inMilliseconds.toString() ?? 'unknown',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    
    handler.next(err);
  }
}
