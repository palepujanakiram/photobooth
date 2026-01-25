import 'package:dio/dio.dart';
import 'package:bugsnag_flutter/bugsnag_flutter.dart';
import '../utils/constants.dart';

/// Bugsnag Dio Interceptor
/// Automatically captures all network requests as breadcrumbs in Bugsnag
/// This provides a trail of API calls with detailed timing and performance metrics
class BugsnagDioInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!AppConstants.kEnableLogOutput) {
      handler.next(options);
      return;
    }
    try {
      // Store request start time for duration tracking
      options.extra['bugsnag_request_start'] = DateTime.now();
      
      // Calculate request size
      int requestSize = 0;
      try {
        if (options.data is String) {
          requestSize = (options.data as String).length;
        } else if (options.data is Map || options.data is List) {
          requestSize = options.data.toString().length;
        }
      } catch (_) {}
      
      // Leave breadcrumb for network request
      bugsnag.leaveBreadcrumb(
        'HTTP Request: ${options.method} ${options.uri.path}',
        metadata: {
          'type': 'request',
          'method': options.method,
          'url': options.uri.toString(),
          'path': options.uri.path,
          'request_size_bytes': requestSize,
          'timestamp': DateTime.now().toIso8601String(),
        },
        type: BugsnagBreadcrumbType.navigation,
      );
    } catch (e) {
      // Silently fail - don't break app if Bugsnag has issues
    }
    
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (!AppConstants.kEnableLogOutput) {
      handler.next(response);
      return;
    }
    try {
      // Calculate request duration
      final startTime = response.requestOptions.extra['bugsnag_request_start'] as DateTime?;
      final durationMs = startTime != null 
          ? DateTime.now().difference(startTime).inMilliseconds 
          : null;
      
      // Calculate response size
      int responseSize = 0;
      try {
        if (response.data is String) {
          responseSize = (response.data as String).length;
        } else if (response.data is List<int>) {
          responseSize = (response.data as List<int>).length;
        } else if (response.data != null) {
          responseSize = response.data.toString().length;
        }
      } catch (_) {}
      
      // Calculate throughput
      double? throughputKBps;
      if (durationMs != null && durationMs > 0 && responseSize > 0) {
        throughputKBps = (responseSize / 1024) / (durationMs / 1000);
      }
      
      // Leave breadcrumb for successful response with detailed metrics
      bugsnag.leaveBreadcrumb(
        'HTTP Response: ${response.requestOptions.method} ${response.requestOptions.uri.path} - ${response.statusCode} (${durationMs ?? "?"}ms)',
        metadata: {
          'type': 'response',
          'method': response.requestOptions.method,
          'url': response.requestOptions.uri.toString(),
          'status_code': response.statusCode ?? 0,
          'status_message': response.statusMessage ?? '',
          'duration_ms': durationMs ?? 0,
          'response_size_bytes': responseSize,
          'throughput_kbps': throughputKBps?.toStringAsFixed(2) ?? 'N/A',
          'timestamp': DateTime.now().toIso8601String(),
        },
        type: BugsnagBreadcrumbType.navigation,
      );
    } catch (e) {
      // Silently fail
    }
    
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (!AppConstants.kEnableLogOutput) {
      handler.next(err);
      return;
    }
    try {
      // Calculate request duration
      final startTime = err.requestOptions.extra['bugsnag_request_start'] as DateTime?;
      final durationMs = startTime != null 
          ? DateTime.now().difference(startTime).inMilliseconds 
          : null;
      
      // Leave breadcrumb for error with timing
      bugsnag.leaveBreadcrumb(
        'HTTP Error: ${err.requestOptions.method} ${err.requestOptions.uri.path} - ${err.type.name} (${durationMs ?? "?"}ms)',
        metadata: {
          'type': 'error',
          'method': err.requestOptions.method,
          'url': err.requestOptions.uri.toString(),
          'error_type': err.type.name,
          'error_message': err.message ?? 'No message',
          'status_code': err.response?.statusCode?.toString() ?? 'none',
          'duration_ms': durationMs ?? 0,
          'timestamp': DateTime.now().toIso8601String(),
        },
        type: BugsnagBreadcrumbType.error,
      );
    } catch (e) {
      // Silently fail
    }
    
    handler.next(err);
  }
}
