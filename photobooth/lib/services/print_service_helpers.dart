import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../utils/exceptions.dart';
import '../utils/logger.dart';
import 'alice_inspector.dart';
import 'api_logging_interceptor.dart';
import 'dio_web_config_stub.dart' if (dart.library.html) 'dio_web_config.dart';
import 'error_reporting/error_reporting_manager.dart';
import 'file_helper.dart';
import 'print_file.dart';
import 'printer_api_client.dart';

/// Resolves image bytes from a local file or http(s) URL for network print.
Future<List<int>> loadImageBytesForNetworkPrint(XFile imageFile) async {
  final filePath = imageFile.path;
  if (filePath.startsWith('http://') || filePath.startsWith('https://')) {
    AppLogger.debug('📥 Downloading image from URL for printing: $filePath');
    final downloadDio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    configureDioForWeb(downloadDio);
    if (kDebugMode) {
      downloadDio.interceptors.add(ApiLoggingInterceptor());
      downloadDio.interceptors.add(AliceDioProxyInterceptor());
    }
    final response = await downloadDio.get<List<int>>(
      filePath,
      options: Options(responseType: ResponseType.bytes),
    );
    final imageBytes = response.data ?? [];
    if (imageBytes.isEmpty) {
      throw PrintException('Downloaded image from URL is empty');
    }
    AppLogger.debug('✅ Downloaded ${imageBytes.length} bytes from URL');
    return imageBytes;
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

Future<void> postNetworkPrintWeb(Dio dio, String baseUrl, List<int> imageBytes) async {
  final formData = FormData.fromMap({
    'imageFile': MultipartFile.fromBytes(
      imageBytes,
      filename: 'image.jpg',
    ),
    'printSize': 's4x6',
    'quantity': 1,
    'imageEdited': false,
    'DeviceId': 'flutter-photobooth-web',
  });
  AppLogger.debug('🖨️ Sending print request to $baseUrl/api/PrintImage');
  await dio.post(
    '/api/PrintImage',
    data: formData,
    options: Options(contentType: 'multipart/form-data'),
  );
  AppLogger.debug('✅ Print request sent successfully (web)');
}

Future<void> postNetworkPrintMobile({
  required PrinterApiClient printerClient,
  required List<int> imageBytes,
  required String baseUrl,
}) async {
  final tempDirPath = await FileHelper.getTempDirectoryPath();
  final fileName = 'print_${DateTime.now().millisecondsSinceEpoch}.jpg';
  final filePath = '$tempDirPath/$fileName';
  final PrintFile tempFile = createPrintFile(filePath);
  await tempFile.writeAsBytes(imageBytes);
  AppLogger.debug('🖨️ Sending print request to $baseUrl/api/PrintImage');
  try {
    await printerClient.printImage(
      tempFile.retrofitFile,
      's4x6',
      1,
      false,
      'flutter-photobooth-mobile',
    );
    AppLogger.debug('✅ Print request sent successfully (mobile)');
  } finally {
    if (tempFile.existsSync()) {
      await tempFile.delete();
    }
  }
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
