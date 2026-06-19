// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import 'package:photobooth/utils/app_config.dart';
import 'package:photobooth/utils/image_helper_encode.dart';

/// Smoke-test PATCH /api/sessions/:id with a tiny JPEG data URL.
Future<void> main(List<String> args) async {
  var kioskCode = 'TEST';
  for (final arg in args) {
    if (arg.startsWith('--kiosk-code=')) {
      kioskCode = arg.substring('--kiosk-code='.length).trim();
    }
  }

  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.baseUrl,
      headers: AppConfig.authorizationBearerHeader,
      connectTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 120),
      receiveTimeout: const Duration(seconds: 120),
    ),
  );

  print('baseUrl: ${AppConfig.baseUrl}');
  print('Creating session (kioskCode=$kioskCode)...');
  final terms = await dio.post<Map<String, dynamic>>(
    '/api/sessions/accept-terms',
    data: {'kioskCode': kioskCode, 'acceptedTerms': true},
  );
  print('accept-terms HTTP ${terms.statusCode}');
  final sessionId = terms.data?['id']?.toString();
  final token = terms.data?['kioskAuthToken']?.toString();
  if (sessionId == null) {
    print('ERROR: no session id in response: ${terms.data}');
    return;
  }
  print('sessionId=$sessionId kioskToken=${token != null}');

  final useLarge = args.contains('--large');
  final String dataUrl;
  if (useLarge) {
    final bytes = img.encodeJpg(img.Image(width: 1920, height: 1080), quality: 85);
    dataUrl = await encodeSessionPatchUserImageUrlAsync(
      Uint8List.fromList(bytes),
    );
  } else {
    final jpeg = img.encodeJpg(img.Image(width: 64, height: 48), quality: 80);
    dataUrl = 'data:image/jpeg;base64,${base64Encode(jpeg)}';
  }
  print('dataUrl length=${dataUrl.length}');

  final sw = Stopwatch()..start();
  try {
    final patch = await dio.patch<String>(
      '/api/sessions/$sessionId',
      data: {
        'userImageUrl': dataUrl,
        'framingMetadata': {
          'applied': false,
          'mode': 'auto',
          'originalImageUrl': null,
        },
      },
      options: Options(
        responseType: ResponseType.plain,
        headers: {if (token != null) 'X-Kiosk-Session-Token': token},
      ),
    );
    print('PATCH ok in ${sw.elapsedMilliseconds}ms HTTP ${patch.statusCode}');
    print('response length=${patch.data?.length ?? 0}');
  } on DioException catch (e) {
    print(
      'PATCH fail in ${sw.elapsedMilliseconds}ms type=${e.type} '
      'HTTP ${e.response?.statusCode}',
    );
    print('message=${e.message}');
    final d = e.response?.data;
    if (d is String && d.length < 800) print('body=$d');
  }
}
