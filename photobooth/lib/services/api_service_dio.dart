import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;

import '../utils/app_config.dart';
import '../utils/app_strings.dart';
import '../utils/constants.dart';
import 'alice_inspector.dart';
import 'api_logging_interceptor.dart';
import 'client_identification.dart';
import 'dio_web_config_stub.dart' if (dart.library.html) 'dio_web_config.dart';
import 'kiosk_session_auth.dart';

/// Production Dio for [ApiService] (interceptors, web CORS mapping).
Dio createProductionApiDio() {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConstants.kBaseUrl,
      connectTimeout: AppConstants.kApiTimeout,
      receiveTimeout: AppConstants.kApiTimeout,
      sendTimeout: AppConstants.kApiTimeout,
      headers: ClientIdentification.mergeHeaders({
        'Content-Type': 'application/json',
        ...AppConfig.authorizationBearerHeader,
      }),
    ),
  );

  configureDioForWeb(dio);

  if (kDebugMode == true) {
    dio.interceptors.add(ApiLoggingInterceptor());
    dio.interceptors.add(AliceDioProxyInterceptor());
  }

  addKioskSessionTokenInterceptor(dio);

  dio.interceptors.add(
    InterceptorsWrapper(
      onError: (error, handler) {
        if (kIsWeb) {
          final dioError = error;
          if (dioError.type == DioExceptionType.connectionError ||
              dioError.type == DioExceptionType.unknown) {
            final errorMsg = dioError.message ?? '';
            if (errorMsg.contains('XMLHttpRequest') ||
                errorMsg.contains('CORS') ||
                errorMsg.contains(AppStrings.failedToFetch) ||
                errorMsg.contains('NetworkError') ||
                errorMsg.contains('connection errored') ||
                errorMsg.contains('assureDioException') ||
                errorMsg.contains('SocketException') ||
                errorMsg.contains('Failed host lookup')) {
              final friendlyError = DioException(
                requestOptions: dioError.requestOptions,
                type: DioExceptionType.connectionError,
                error:
                    'CORS/Network Error: The API server may not be configured to allow requests from this origin.',
                message:
                    'CORS/Network Error: ${dioError.message ?? AppStrings.unknownNetworkError}',
              );
              return handler.next(friendlyError);
            }
          }
        }
        return handler.next(error);
      },
    ),
  );

  return dio;
}

/// Dio for AI generation when tests do not inject [aiDio].
Dio createAiGenerationDio({bool sseAccept = false}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConstants.kBaseUrl,
      connectTimeout: AppConstants.kAiGenerationTimeout,
      receiveTimeout: AppConstants.kAiGenerationTimeout,
      sendTimeout: AppConstants.kAiGenerationTimeout,
      headers: ClientIdentification.mergeHeaders({
        if (sseAccept) 'Accept': 'text/event-stream',
        if (!sseAccept) 'Content-Type': 'application/json',
        ...AppConfig.authorizationBearerHeader,
      }),
    ),
  );
  configureDioForWeb(dio);
  if (kDebugMode == true) {
    dio.interceptors.add(ApiLoggingInterceptor());
    dio.interceptors.add(AliceDioProxyInterceptor());
  }
  addKioskSessionTokenInterceptor(dio);
  return dio;
}
