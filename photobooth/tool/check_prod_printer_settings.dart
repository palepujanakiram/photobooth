// ignore_for_file: avoid_print
import 'package:dio/dio.dart';
import 'package:photobooth/utils/app_config.dart';

/// Prints printer-related fields from `/api/settings`.
Future<void> main(List<String> args) async {
  var baseUrl = AppConfig.baseUrl;
  for (final arg in args) {
    if (arg.startsWith('--base-url=')) {
      baseUrl = arg.substring('--base-url='.length).trim();
    }
  }

  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      headers: {
        ...AppConfig.authorizationBearerHeader,
        'Accept': 'application/json',
      },
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );

  try {
    final response = await dio.get<Map<String, dynamic>>('/api/settings');
    final data = response.data;
    if (data == null) {
      print('ERROR: empty response');
      return;
    }
    print('baseUrl: $baseUrl');
    for (final key in [
      'printerEnabled',
      'printerHost',
      'printerPort',
      'printerPath',
      'paymentGatewayEnabled',
    ]) {
      print('$key: ${data[key]}');
    }
  } on DioException catch (e) {
    print('ERROR: ${e.type} HTTP ${e.response?.statusCode}');
  }
}
