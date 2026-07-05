import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:uuid/uuid.dart';

import '../utils/app_strings.dart';
import '../utils/constants.dart';
import '../utils/exceptions.dart';
import '../utils/logger.dart';
import 'api_logging_interceptor.dart';
import 'alice_inspector.dart';
import 'dio_web_config_stub.dart' if (dart.library.html) 'dio_web_config.dart';
import 'api_service_legacy_media.dart';
import 'client_identification.dart';
import 'staff_session_manager.dart';

class StaffApiService {
  StaffApiService({
    Dio? dio,
    StaffSessionManager? sessionManager,
  })  : _dio = dio ?? Dio(),
        _sessionManager = sessionManager ?? StaffSessionManager() {
    _dio.options = BaseOptions(
      baseUrl: AppConstants.kBaseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      headers: ClientIdentification.mergeHeaders({
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      }),
    );

    configureDioForWeb(_dio);

    if (kDebugMode == true) {
      _dio.interceptors.add(ApiLoggingInterceptor());
      _dio.interceptors.add(AliceDioProxyInterceptor());
    }

    // Mirror the web-friendly error normalization in ApiService.
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) {
          if (kIsWeb) {
            if (error.type == DioExceptionType.connectionError ||
                error.type == DioExceptionType.unknown) {
              final msg = error.message ?? '';
              final isCors = msg.contains('XMLHttpRequest') ||
                  msg.contains('CORS') ||
                  msg.contains('Failed to fetch') ||
                  msg.contains('NetworkError') ||
                  msg.contains('SocketException') ||
                  msg.contains('Failed host lookup');
              if (isCors) {
                return handler.next(
                  DioException(
                    requestOptions: error.requestOptions,
                    type: DioExceptionType.connectionError,
                    error:
                        'CORS/Network Error: The API server may not allow requests from this origin.',
                    message: 'CORS/Network Error: $msg',
                  ),
                );
              }
            }
          }
          return handler.next(error);
        },
      ),
    );
  }

  final Dio _dio;
  final StaffSessionManager _sessionManager;

  Future<Map<String, dynamic>> staffLookupWithCode({
    required String staffCode,
    required String accountName,
  }) async {
    final code = staffCode.trim();
    final acct = accountName.trim();
    if (code.isEmpty || acct.isEmpty) {
      throw ApiException('Enter staff code and account name');
    }

    try {
      final r = await _dio.post<dynamic>(
        '/api/staff/lookup',
        data: <String, dynamic>{
          'staffCode': code,
          'accountName': acct,
        },
        options: Options(
          validateStatus: (c) => c != null && c >= 200 && c < 500,
          responseType: ResponseType.json,
        ),
      );

      if (r.statusCode == 200) {
        final data = _asJsonMap(r.data);
        final token = (data['sessionToken'] ?? '').toString().trim();
        if (token.isEmpty) {
          throw ApiException('Login succeeded but sessionToken is missing');
        }
        final staff = data['staff'];
        final staffJson = jsonEncode(staff ?? {});
        await _sessionManager.setSession(token: token, staffJson: staffJson);
        return data;
      }

      final err = _extractErrorMessage(r.data) ??
          (r.statusCode == 404
              ? 'Staff not found or inactive'
              : 'Failed to lookup staff');
      throw ApiException(err, r.statusCode);
    } on DioException catch (e) {
      throw ApiException(
        e.message ?? 'Network error while logging in',
        e.response?.statusCode,
      );
    }
  }

  Future<void> logout() async {
    final token = await _sessionManager.getToken();
    try {
      if (token != null && token.isNotEmpty) {
        await _dio.post<dynamic>(
          '/api/staff/logout',
          options: Options(
            headers: {AppStrings.staffTokenHeader: token},
            validateStatus: (c) => c != null && c >= 200 && c < 500,
          ),
        );
      }
    } catch (e, st) {
      AppLogger.error(
        'Staff logout error (non-fatal, ignored)',
        error: e,
        stackTrace: st,
      );
    } finally {
      await _sessionManager.clear();
    }
  }

  Future<List<Map<String, dynamic>>> listPayments() async {
    final token = await _sessionManager.getToken();
    if (token == null || token.isEmpty) {
      throw ApiException('Staff session expired. Please log in again.');
    }

    try {
      final r = await _dio.get<dynamic>(
        '/api/staff/payments',
        options: Options(
          headers: {AppStrings.staffTokenHeader: token},
          validateStatus: (c) => c != null && c >= 200 && c < 500,
          responseType: ResponseType.json,
        ),
      );

      if (r.statusCode == 200) {
        final data = r.data;
        if (data is List) {
          return data.map((e) => _asJsonMap(e)).toList();
        }
        if (data is Map) {
          final m = Map<String, dynamic>.from(data);
          final list = m['payments'];
          if (list is List) {
            return list.map((e) => _asJsonMap(e)).toList();
          }
        }
        return const [];
      }

      throw ApiException(
        _extractErrorMessage(r.data) ?? 'Failed to fetch payments',
        r.statusCode,
      );
    } on DioException catch (e) {
      throw ApiException(
        e.message ?? 'Network error while fetching payments',
        e.response?.statusCode,
      );
    }
  }

  /// GET `/api/sessions/:id` with staff auth (privileged read for thumbnails/print).
  Future<Map<String, dynamic>?> fetchSession(String sessionId) async {
    final sid = sessionId.trim();
    if (sid.isEmpty) return null;

    final token = await _sessionManager.getToken();
    if (token == null || token.isEmpty) {
      throw ApiException('Staff session expired. Please log in again.');
    }

    try {
      final r = await _dio.get<dynamic>(
        '/api/sessions/$sid',
        options: Options(
          headers: {AppStrings.staffTokenHeader: token},
          validateStatus: (c) => c != null && c >= 200 && c < 500,
          responseType: ResponseType.json,
        ),
      );
      if (r.statusCode != 200) return null;

      final raw = _asJsonMap(r.data);
      if (!_isSessionPayload(raw, expectedId: sid)) {
        if (kDebugMode) {
          AppLogger.debug(
            'Staff fetchSession ignored non-session response for $sid',
          );
        }
        return null;
      }
      return raw;
    } on DioException catch (e) {
      if (kDebugMode) {
        AppLogger.debug(
          'Staff fetchSession /api/sessions/$sid failed: ${e.message}',
        );
      }
      return null;
    }
  }

  /// Download a protected `/api/img/*` URL using staff auth (for print flow).
  Future<XFile> downloadImageToTemp(
    String imageUrl, {
    void Function(String message)? onProgress,
  }) async {
    final token = await _sessionManager.getToken();
    if (token == null || token.isEmpty) {
      throw ApiException('Staff session expired. Please log in again.');
    }

    final dio = Dio(_dio.options);
    configureDioForWeb(dio);
    dio.options = dio.options.copyWith(
      headers: {
        ...dio.options.headers,
        AppStrings.staffTokenHeader: token,
      },
    );

    return ApiServiceLegacyMedia.downloadImageToTemp(
      dio: dio,
      uuid: const Uuid(),
      imageUrl: imageUrl,
      onProgress: onProgress,
    );
  }

  Future<void> approvePayment({required String paymentId}) async {
    await _postWithToken(
      '/api/staff/payment/approve',
      data: {'paymentId': paymentId},
      defaultError: 'Failed to approve payment',
    );
  }

  Future<void> rejectPayment({required String paymentId}) async {
    await _postWithToken(
      '/api/staff/payment/reject',
      data: {'paymentId': paymentId},
      defaultError: 'Failed to reject payment',
    );
  }

  Future<void> createPrintJob({
    required String sessionId,
    required String imageUrl,
    String? paymentId,
  }) async {
    final sid = sessionId.trim();
    final img = imageUrl.trim();
    if (sid.isEmpty || img.isEmpty) {
      throw ApiException('sessionId and imageUrl are required');
    }

    // Some backend validators use lowercase keys; send both to be safe.
    final payload = <String, dynamic>{
      'sessionId': sid,
      'sessionid': sid,
      'imageUrl': img,
      'imageurl': img,
    };
    final pid = paymentId?.trim();
    if (pid != null && pid.isNotEmpty) {
      payload['paymentId'] = pid;
      payload['paymentid'] = pid;
    }

    await _postWithToken(
      '/api/staff/print',
      data: payload,
      defaultError: 'Failed to create print job',
    );
  }

  Future<void> _postWithToken(
    String path, {
    required Map<String, dynamic> data,
    required String defaultError,
  }) async {
    final token = await _sessionManager.getToken();
    if (token == null || token.isEmpty) {
      throw ApiException('Staff session expired. Please log in again.');
    }
    try {
      final r = await _dio.post<dynamic>(
        path,
        data: data,
        options: Options(
          headers: {AppStrings.staffTokenHeader: token},
          validateStatus: (c) => c != null && c >= 200 && c < 500,
          responseType: ResponseType.json,
        ),
      );
      if (r.statusCode != null && r.statusCode! >= 200 && r.statusCode! < 300) {
        return;
      }
      throw ApiException(
        _extractErrorMessage(r.data) ?? defaultError,
        r.statusCode,
      );
    } on DioException catch (e) {
      throw ApiException(
        e.message ?? defaultError,
        e.response?.statusCode,
      );
    }
  }

  static bool _isSessionPayload(
    Map<String, dynamic> raw, {
    required String expectedId,
  }) {
    final id = raw['id']?.toString().trim();
    return id != null && id.isNotEmpty && id == expectedId;
  }

  static Map<String, dynamic> _asJsonMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    AppLogger.error(
      'Staff endpoint returned non-Map response: ${data.runtimeType}',
    );
    return const <String, dynamic>{};
  }

  static String? _extractErrorMessage(dynamic data) {
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      final err = m['error']?.toString().trim();
      if (err != null && err.isNotEmpty) return err;
      final msg = m['message']?.toString().trim();
      if (msg != null && msg.isNotEmpty) return msg;
    }
    if (data is String) {
      final t = data.trim();
      return t.isEmpty ? null : t;
    }
    return null;
  }
}

