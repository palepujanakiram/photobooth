import 'package:dio/dio.dart';
import 'package:bugsnag_flutter/bugsnag_flutter.dart';

/// Bugsnag Dio Interceptor
/// Automatically captures all network requests as breadcrumbs in Bugsnag
/// This provides a trail of API calls leading up to any error
class BugsnagDioInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    try {
      // Leave breadcrumb for network request
      bugsnag.leaveBreadcrumb(
        'HTTP Request: ${options.method} ${options.uri.path}',
        metadata: {
          'type': 'request',
          'method': options.method,
          'url': options.uri.toString(),
          'path': options.uri.path,
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
    try {
      // Leave breadcrumb for successful response
      bugsnag.leaveBreadcrumb(
        'HTTP Response: ${response.requestOptions.method} ${response.requestOptions.uri.path} - ${response.statusCode}',
        metadata: {
          'type': 'response',
          'method': response.requestOptions.method,
          'url': response.requestOptions.uri.toString(),
          'status_code': response.statusCode ?? 0,
          'status_message': response.statusMessage ?? '',
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
    try {
      // Leave breadcrumb for error
      bugsnag.leaveBreadcrumb(
        'HTTP Error: ${err.requestOptions.method} ${err.requestOptions.uri.path} - ${err.type.name}',
        metadata: {
          'type': 'error',
          'method': err.requestOptions.method,
          'url': err.requestOptions.uri.toString(),
          'error_type': err.type.name,
          'error_message': err.message ?? 'No message',
          'status_code': err.response?.statusCode?.toString() ?? 'none',
        },
        type: BugsnagBreadcrumbType.error,
      );
    } catch (e) {
      // Silently fail
    }
    
    handler.next(err);
  }
}
