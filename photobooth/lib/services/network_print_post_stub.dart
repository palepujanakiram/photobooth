import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../utils/constants.dart';
import '../utils/logger.dart';
import '../utils/printer_endpoint.dart';
import 'alice_inspector.dart';
import 'api_logging_interceptor.dart';
import 'dio_web_config_stub.dart'
    if (dart.library.html) 'dio_web_config.dart';

/// Native (VM) Dio client for LAN / WCM printer HTTP.
Dio createPrinterApiDio(String baseUrl) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      headers: {
        'Accept': 'application/json, text/plain, */*',
        'Accept-Encoding': 'gzip, deflate',
        'Accept-Language':
            'en-IN,en;q=0.9,te-IN;q=0.8,te;q=0.7,en-GB;q=0.6,en-US;q=0.5',
        'Connection': 'keep-alive',
        'Origin': baseUrl,
        'Referer': '$baseUrl/print',
        'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
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

/// True when Dio reports an error but the LAN printer likely already accepted
/// the JPEG (slow response / connection reset after accept).
bool lanPrintResponseUncertainButJobLikelySent(DioException e) {
  if (e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout) {
    return true;
  }
  if (e.type != DioExceptionType.connectionError &&
      e.type != DioExceptionType.unknown) {
    return false;
  }
  final msg = '${e.message ?? ''} ${e.error ?? ''}'.toLowerCase();
  return msg.contains('connection reset') ||
      msg.contains('connection closed') ||
      msg.contains('broken pipe') ||
      msg.contains('software caused connection abort') ||
      msg.contains('stream closed') ||
      msg.contains('connection abort') ||
      msg.contains('socketexception') ||
      msg.contains('http connection was closed') ||
      msg.contains('unexpected end of stream');
}

Future<void> postNetworkPrintMultipart({
  required Dio dio,
  required String apiPath,
  required List<int> imageBytes,
  String printSize = AppConstants.kPrintSizePortrait4x6,
  required String deviceId,
  int quantity = AppConstants.kDefaultPrintCopies,
}) async {
  final copies = quantity.clamp(
    AppConstants.kDefaultPrintCopies,
    AppConstants.kMaxPrintCopies,
  );
  final formData = FormData.fromMap({
    'imageFile': MultipartFile.fromBytes(
      imageBytes,
      filename: 'image.jpg',
    ),
    'printSize': printSize,
    'quantity': copies,
    'imageEdited': false,
    'DeviceId': deviceId,
  });
  AppLogger.debug('🖨️ Sending print request to ${dio.options.baseUrl}$apiPath');
  try {
    await dio.post(
      apiPath,
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );
  } on DioException catch (e) {
    if (lanPrintResponseUncertainButJobLikelySent(e)) {
      AppLogger.warning(
        'LAN printer HTTP response inconclusive (multipart); '
        'assuming job accepted: $e',
      );
      return;
    }
    rethrow;
  }
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
  try {
    await dio.post<void>(
      apiPath,
      data: imageBytes,
      options: Options(
        contentType: 'image/jpeg',
        responseType: ResponseType.plain,
      ),
    );
  } on DioException catch (e) {
    if (lanPrintResponseUncertainButJobLikelySent(e)) {
      AppLogger.warning(
        'LAN printer HTTP response inconclusive (raw JPEG); '
        'assuming job accepted: $e',
      );
      return;
    }
    rethrow;
  }
  AppLogger.debug('✅ Raw JPEG print request sent successfully');
}

/// Posts a print job to a LAN printer (native: Dio).
///
/// Always issues one HTTP job per copy — many DNP/WCM firmwares ignore or
/// mishandle multipart `quantity` > 1.
Future<void> postLanPrinterMultipart({
  required String baseUrl,
  required String apiPath,
  required List<int> imageBytes,
  required String printSize,
  required String deviceId,
  int quantity = 1,
}) async {
  final dio = createPrinterApiDio(baseUrl);
  final copies = quantity < 1 ? 1 : quantity;
  try {
    if (usesDnpMultipartPrintApi(apiPath)) {
      for (var i = 0; i < copies; i++) {
        await postNetworkPrintMultipart(
          dio: dio,
          apiPath: apiPath,
          imageBytes: imageBytes,
          printSize: printSize,
          deviceId: deviceId,
          quantity: 1,
        );
      }
      return;
    }
    for (var i = 0; i < copies; i++) {
      await postRawJpegNetworkPrint(
        dio: dio,
        apiPath: apiPath,
        imageBytes: imageBytes,
      );
    }
  } finally {
    dio.close(force: true);
  }
}
