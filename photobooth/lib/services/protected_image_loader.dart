import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../utils/app_config.dart';
import '../utils/constants.dart';
import '../utils/secure_image_url.dart';
import 'client_identification.dart';
import 'dio_web_config_stub.dart' if (dart.library.html) 'dio_web_config.dart';
import 'kiosk_session_auth.dart';

/// Loads `/api/img/*` resources with kiosk session auth headers.
///
/// [Image.network] cannot send `X-Kiosk-Session-Token`; use this for protected URLs.
class ProtectedImageLoader {
  ProtectedImageLoader._();

  static final ProtectedImageLoader instance = ProtectedImageLoader._();

  static final Dio _dio = _createDio();

  static Dio _createDio() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: AppConstants.kApiTimeout,
        receiveTimeout: AppConstants.kApiTimeout,
        headers: ClientIdentification.mergeHeaders({
          ...AppConfig.authorizationBearerHeader,
        }),
      ),
    );
    configureDioForWeb(dio);
    addKioskSessionTokenInterceptor(dio);
    return dio;
  }

  /// True when the URL targets a server-protected image under `/api/img/`.
  static bool isProtectedUrl(String url) {
    try {
      final uri = Uri.parse(SecureImageUrl.absolutize(url));
      return uri.path.startsWith('/api/img/');
    } catch (_) {
      return false;
    }
  }

  /// Fetches image bytes with `X-Kiosk-Session-Token` (and bearer auth if configured).
  Future<Uint8List> fetchBytes(String url) async {
    final secured = SecureImageUrl.withSessionId(SecureImageUrl.absolutize(url));
    final uri = Uri.parse(secured);
    final response = await _dio.getUri<Uint8List>(
      uri,
      options: Options(
        responseType: ResponseType.bytes,
        validateStatus: (c) => c != null && c >= 200 && c < 300,
      ),
    );
    final data = response.data;
    if (data == null || data.isEmpty) {
      throw Exception(
        'Failed to load protected image (${response.statusCode ?? 'unknown'})',
      );
    }
    return data;
  }
}
