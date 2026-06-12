// ignore_for_file: avoid_print
import 'package:dio/dio.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/utils/app_config.dart';

/// Fetches `/api/settings` and prints `showGenerationCommentary` for a given base URL.
///
/// Usage:
///   dart run tool/check_prod_settings.dart
///   dart run tool/check_prod_settings.dart --base-url=https://fotozenai.fly.dev
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
      print('ERROR: empty response body (HTTP ${response.statusCode})');
      return;
    }
    final settings = AppSettingsModel.fromJson(data);
    final flag = settings.showGenerationCommentary;
    print('baseUrl: $baseUrl');
    print('HTTP: ${response.statusCode}');
    print('showGenerationCommentary: $flag');
    print('enabled: ${flag == true}');
  } on DioException catch (e) {
    print('ERROR: ${e.type} HTTP ${e.response?.statusCode}');
    final body = e.response?.data;
    if (body != null) print('body: $body');
  }
}
