import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../utils/constants.dart';
import '../utils/exceptions.dart';
import '../utils/logger.dart';
import '../utils/secure_image_url.dart';
import 'alice_inspector.dart';
import 'api_logging_interceptor.dart';
import 'dio_web_config_stub.dart' if (dart.library.html) 'dio_web_config.dart';
import 'error_reporting/error_reporting_manager.dart';
import 'kiosk_session_auth.dart';
import 'protected_image_loader.dart';

/// Absolute URL with `sessionId` for protected `/api/img/*` resources.
String resolveRemoteImageUrlForPrint(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return trimmed;

  final absolute = trimmed.startsWith('http://') || trimmed.startsWith('https://')
      ? trimmed
      : SecureImageUrl.absolutize(trimmed);
  return SecureImageUrl.withSessionId(absolute);
}

bool _isRemoteImagePath(String path) {
  final trimmed = path.trim();
  return trimmed.startsWith('http://') ||
      trimmed.startsWith('https://') ||
      trimmed.startsWith('/api/img/') ||
      trimmed.startsWith('api/img/');
}

/// Resolves image bytes from a local file or http(s) URL for network print.
Future<List<int>> loadImageBytesForNetworkPrint(XFile imageFile) async {
  final filePath = imageFile.path;
  if (_isRemoteImagePath(filePath)) {
    final url = resolveRemoteImageUrlForPrint(filePath);
    AppLogger.debug('📥 Downloading image for printing: $url');

    if (ProtectedImageLoader.isProtectedUrl(url)) {
      final bytes = await ProtectedImageLoader.instance.fetchBytes(url);
      AppLogger.debug('✅ Loaded ${bytes.length} protected image bytes for print');
      return bytes;
    }

    final downloadDio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    try {
      configureDioForWeb(downloadDio);
      if (kDebugMode) {
        downloadDio.interceptors.add(ApiLoggingInterceptor());
        downloadDio.interceptors.add(AliceDioProxyInterceptor());
      }
      addKioskSessionTokenInterceptor(downloadDio);
      final response = await downloadDio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final imageBytes = response.data ?? [];
      if (imageBytes.isEmpty) {
        throw PrintException('Downloaded image from URL is empty');
      }
      AppLogger.debug('✅ Downloaded ${imageBytes.length} bytes from URL');
      return imageBytes;
    } finally {
      downloadDio.close(force: true);
    }
  }
  return imageFile.readAsBytes();
}

Dio createPrinterApiDio(String baseUrl) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Accept': 'application/json, text/plain, */*',
        'Accept-Encoding': 'gzip, deflate',
        'Accept-Language': 'en-IN,en;q=0.9,te-IN;q=0.8,te;q=0.7,en-GB;q=0.6,en-US;q=0.5',
        'Connection': 'keep-alive',
        'Origin': baseUrl,
        'Referer': '$baseUrl/print',
        'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
      },
    ),
  );
  configureDioForWeb(dio);
  if (kDebugMode) {
    dio.interceptors.add(ApiLoggingInterceptor());
    dio.interceptors.add(AliceDioProxyInterceptor());
  }
  return dio;
}

Future<void> postNetworkPrintMultipart({
  required Dio dio,
  required String apiPath,
  required List<int> imageBytes,
  String printSize = AppConstants.kPrintSizePortrait4x6,
  required String deviceId,
}) async {
  final formData = FormData.fromMap({
    'imageFile': MultipartFile.fromBytes(
      imageBytes,
      filename: 'image.jpg',
    ),
    'printSize': printSize,
    'quantity': 1,
    'imageEdited': false,
    'DeviceId': deviceId,
  });
  AppLogger.debug('🖨️ Sending print request to ${dio.options.baseUrl}$apiPath');
  await dio.post(
    apiPath,
    data: formData,
    options: Options(contentType: 'multipart/form-data'),
  );
  AppLogger.debug('✅ Print request sent successfully');
}

/// Posts raw JPEG bytes for WCM Plus / custom HTTP print endpoints.
Future<void> postRawJpegNetworkPrint({
  required Dio dio,
  required String apiPath,
  required List<int> imageBytes,
}) async {
  AppLogger.debug(
    '🖨️ Sending raw JPEG print to ${dio.options.baseUrl}$apiPath '
    '(${imageBytes.length} bytes)',
  );
  await dio.post<void>(
    apiPath,
    data: imageBytes,
    options: Options(
      contentType: 'image/jpeg',
      responseType: ResponseType.plain,
    ),
  );
  AppLogger.debug('✅ Raw JPEG print request sent successfully');
}

Never throwMappedNetworkPrintDioError(DioException e, String baseUrl) {
  String errorMessage = 'Failed to print image';
  String errorType = 'unknown';

  if (e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout) {
    errorType = 'timeout';
    errorMessage =
        'Connection to printer timed out. Please check the printer address and port.';
  } else if (e.type == DioExceptionType.connectionError) {
    errorType = 'connection_error';
    errorMessage =
        'Cannot connect to printer at $baseUrl. Please check the address, port, and network connection.';
  } else if (e.response != null) {
    errorType = 'http_error';
    errorMessage = 'Print request failed: ${e.response?.statusCode}';
  } else {
    errorType = 'dio_error';
    errorMessage = 'Print request failed: ${e.message ?? 'Unknown error'}';
  }

  AppLogger.error('Print error: $errorMessage', error: e);
  ErrorReportingManager.log('❌ Network print failed: $errorType - $errorMessage');
  throw PrintException(errorMessage);
}
