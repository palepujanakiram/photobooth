import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show compute, kDebugMode, kIsWeb;
import 'package:uuid/uuid.dart';
import '../models/app_settings_model.dart';
import '../models/kiosk_frame_model.dart';
import '../models/kiosk_info_model.dart';
import '../models/payment_initiate_result.dart';
import '../models/parallel_generation_result.dart';
import '../screens/result/transformed_image_model.dart';
import '../screens/theme_selection/theme_model.dart';
import '../utils/exceptions.dart';
import '../utils/app_config.dart';
import '../utils/constants.dart';
import '../utils/session_user_image_validation.dart';
import '../utils/app_strings.dart';
import '../utils/logger.dart';
import 'api_client.dart';
import 'file_helper.dart';
import 'api_dio_errors.dart';
import 'api_http_response.dart';
import 'generation_api_errors.dart';
import 'api_logging_interceptor.dart';
import 'alice_inspector.dart';
import 'client_identification.dart';
import 'kiosk_manager.dart';
import 'session_manager.dart';

// Conditional import for web Dio configuration
import 'dio_web_config_stub.dart' if (dart.library.html) 'dio_web_config.dart';

/// Index of the closing `"` for a JSON string starting at [openQuoteIndex] (`"` itself).
/// Handles standard escapes (`\"`, `\\`, `\uXXXX`, etc.). Returns -1 if not found.
int _jsonStringCloseQuoteIndex(String raw, int openQuoteIndex) {
  var i = openQuoteIndex + 1;
  while (i < raw.length) {
    final ch = raw[i];
    if (ch == r'\') {
      if (i + 1 >= raw.length) return -1;
      final n = raw[i + 1];
      if (n == 'u' && i + 6 <= raw.length) {
        i += 6;
        continue;
      }
      i += 2;
      continue;
    }
    if (ch == '"') return i;
    i++;
  }
  return -1;
}

/// Remove echoed `userImageUrl` string value from raw JSON so [jsonDecode] avoids a multi‑MB field.
/// Uses JSON-aware scanning so escaped `"` inside the value does not truncate early.
String _stripEchoedUserImageUrlField(String raw) {
  const key = '"userImageUrl"';
  final keyIdx = raw.indexOf(key);
  if (keyIdx < 0) return raw;

  final colon = raw.indexOf(':', keyIdx + key.length);
  if (colon < 0) return raw;

  var i = colon + 1;
  while (i < raw.length) {
    final c = raw.codeUnitAt(i);
    if (c != 0x20 && c != 0x09 && c != 0x0a && c != 0x0d) break;
    i++;
  }
  if (i >= raw.length || raw[i] != '"') return raw;

  final valueCloseIdx = _jsonStringCloseQuoteIndex(raw, i);
  if (valueCloseIdx < 0) return raw;

  var removeStart = keyIdx;
  var before = keyIdx - 1;
  while (before >= 0) {
    final c = raw.codeUnitAt(before);
    if (c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d) {
      before--;
      continue;
    }
    if (raw[before] == ',') removeStart = before;
    break;
  }

  var removeEnd = valueCloseIdx + 1;
  while (removeEnd < raw.length) {
    final c = raw.codeUnitAt(removeEnd);
    if (c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d) {
      removeEnd++;
      continue;
    }
    if (c == 0x2c) removeEnd++;
    break;
  }

  return raw.substring(0, removeStart) + raw.substring(removeEnd);
}

/// Dio may get **HTTP 200 + HTML** (proxy error page, missing route behind gateway).
/// [jsonDecode] then fails with `Unexpected token '<'…` — surface a clear [ApiException] instead.
void _assertSessionBodyLooksLikeJson(String raw, String endpointDescription) {
  final s = raw.trimLeft();
  if (s.isEmpty) return;
  if (s.startsWith('<')) {
    throw ApiException(
      'Server returned HTML instead of JSON for $endpointDescription. '
      'Check the API is deployed and the path is correct (got a web page, not JSON).',
    );
  }
  final head = s.length > 9 ? s.substring(0, 9).toLowerCase() : s.toLowerCase();
  if (head.startsWith('<!doctype') || head.startsWith('<html')) {
    throw ApiException(
      'Server returned HTML instead of JSON for $endpointDescription. '
      'Check the API is deployed and the path is correct.',
    );
  }
  if (!s.startsWith('{') && !s.startsWith('[')) {
    throw ApiException(
      'Server returned non-JSON for $endpointDescription. '
      'Expected a JSON object from the API.',
    );
  }
}

/// Decode session PATCH JSON; server often echoes huge `userImageUrl`.
Map<String, dynamic> _parseSessionPatchResponseJson(String raw) {
  _assertSessionBodyLooksLikeJson(raw, 'PATCH /api/sessions/:sessionId');
  try {
    final slim = _stripEchoedUserImageUrlField(raw);
    final decoded = jsonDecode(slim);
    if (decoded is! Map) {
      throw const FormatException('Session PATCH: expected a JSON object');
    }
    final map = Map<String, dynamic>.from(decoded);
    map.remove('userImageUrl');
    return map;
  } on FormatException {
    // Strip can fail on unusual server JSON; full parse + drop key still works (may be heavy).
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw ApiException('Session response was not a JSON object.');
      }
      final map = Map<String, dynamic>.from(decoded);
      map.remove('userImageUrl');
      return map;
    } on FormatException {
      throw ApiException(
        'Could not read session response from the server. '
        'If you recently changed API routes, confirm PATCH /api/sessions returns JSON.',
      );
    }
  }
}

class ApiService {
  late final ApiClient _apiClient;
  late final Dio _dio;
  final Uuid _uuid = const Uuid();

  ApiService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.kBaseUrl,
        connectTimeout: AppConstants.kApiTimeout,
        receiveTimeout: AppConstants.kApiTimeout,
        // Large PATCH bodies (base64 photo) need an explicit send budget on web.
        sendTimeout: AppConstants.kApiTimeout,
        headers: ClientIdentification.mergeHeaders({
          'Content-Type': 'application/json',
          ...AppConfig.authorizationBearerHeader,
        }),
      ),
    );

    // Configure Dio to use browser HTTP adapter on web
    // This prevents SocketException errors from native socket lookups
    configureDioForWeb(_dio);

    if (kDebugMode == true) {
      // Add logging interceptor to log all API calls
      _dio.interceptors.add(ApiLoggingInterceptor());
      _dio.interceptors.add(AliceDioProxyInterceptor());
    }

    // Add error interceptor for web compatibility
    _dio.interceptors.add(InterceptorsWrapper(
      onError: (error, handler) {
        // Handle web-specific errors
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
              // Convert to a more user-friendly error
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
    ));

    _apiClient = ApiClient(_dio, baseUrl: AppConstants.kBaseUrl);
  }

  /// POST `/api/kiosk/shares` — mint a short-lived share link for a session.
  ///
  /// Kiosk-callable (no admin auth). Backend validates kiosk owns the session.
  /// Returns a map with: token, url (short `/s/:token`), longUrl (fallback), expiresAt.
  Future<Map<String, dynamic>> createKioskShareLink({
    required String kioskCode,
    required String sessionId,
    int? ttlMinutes,
    int? imageIndex,
  }) async {
    final code = kioskCode.trim().toUpperCase();
    final sid = sessionId.trim();
    if (code.isEmpty) {
      throw ApiException('kioskCode is required');
    }
    if (sid.isEmpty) {
      throw ApiException('sessionId is required');
    }

    try {
      final body = <String, dynamic>{
        'kioskCode': code,
        'sessionId': sid,
        if (ttlMinutes != null) 'ttlMinutes': ttlMinutes,
        if (imageIndex != null) 'imageIndex': imageIndex,
      };

      final r = await _dio.post<dynamic>(
        '/api/kiosk/shares',
        data: body,
        options: Options(
          responseType: ResponseType.json,
          validateStatus: (c) => c != null && c >= 200 && c < 500,
        ),
      );
      final data = r.data;
      throwIfHttpErrorResponse(r, operationLabel: 'Failed to create share link');
      return parseJsonMapBody(
        data,
        unexpectedMessage: 'Unexpected share link response from API',
      );
    } on DioException catch (e) {
      throwApiExceptionAfterWebCors(
        e,
        messagePrefix: 'Failed to create share link',
      );
    }
  }

  /// POST `/api/sessions/:id/fcm-token` — bind device token to session for silent pushes.
  Future<void> registerSessionFcmToken({
    required String sessionId,
    required String fcmToken,
  }) async {
    final sid = sessionId.trim();
    final token = fcmToken.trim();
    if (sid.isEmpty || token.isEmpty) return;

    try {
      await _dio.post<dynamic>(
        '/api/sessions/$sid/fcm-token',
        data: {'fcmToken': token},
        options: Options(
          responseType: ResponseType.json,
          validateStatus: (c) => c != null && c >= 200 && c < 500,
        ),
      );
    } on DioException catch (e) {
      AppLogger.error(
        'registerSessionFcmToken failed: ${e.message}',
        error: e,
        stackTrace: e.stackTrace,
      );
    } catch (e) {
      AppLogger.error('registerSessionFcmToken failed: $e', error: e);
    }
  }

  /// POST `/api/sessions/:id/receipt` — create/update receipt + optional WhatsApp queue.
  ///
  /// Requires `session.paymentStatus == APPROVED` server-side.
  Future<Map<String, dynamic>> postSessionReceipt({
    required String sessionId,
    String? customerName,
    String? customerPhone,
    bool? whatsappOptIn,
    String? transactionRef,
    String? fcmToken,
  }) async {
    final sid = sessionId.trim();
    if (sid.isEmpty) {
      throw ApiException('sessionId is required');
    }

    final body = <String, dynamic>{
      if (customerName != null && customerName.trim().isNotEmpty)
        'customerName': customerName.trim(),
      if (customerPhone != null && customerPhone.trim().isNotEmpty)
        'customerPhone': customerPhone.trim(),
      if (whatsappOptIn != null) 'whatsappOptIn': whatsappOptIn,
      if (transactionRef != null && transactionRef.trim().isNotEmpty)
        'transactionRef': transactionRef.trim(),
      if (fcmToken != null && fcmToken.trim().isNotEmpty) 'fcmToken': fcmToken.trim(),
    };

    try {
      final r = await _dio.post<dynamic>(
        '/api/sessions/$sid/receipt',
        data: body,
        options: Options(
          responseType: ResponseType.json,
          validateStatus: (c) => c != null && c >= 200 && c < 500,
        ),
      );
      final data = r.data;
      throwIfHttpErrorResponse(r, operationLabel: 'Receipt request failed');
      return parseJsonMapBody(
        data,
        unexpectedMessage: 'Unexpected receipt response from API',
      );
    } on DioException catch (e) {
      throwApiExceptionAfterWebCors(
        e,
        messagePrefix: 'Failed to request receipt',
      );
    }
  }

  /// GET `/api/payments/status/{paymentId}?sessionId=…` — `{ "status": "PENDING" | "APPROVED" | "FAILED" }`.
  ///
  /// [sessionId] is required by the server (query param); omit only in legacy tests.
  Future<Map<String, dynamic>?> fetchPaymentStatus(
    String paymentId, {
    String? sessionId,
  }) async {
    if (paymentId.isEmpty) return null;
    final sid = sessionId?.trim();
    final qp = <String, dynamic>{};
    if (sid != null && sid.isNotEmpty) {
      qp['sessionId'] = sid;
    }
    try {
      final r = await _dio.get<dynamic>(
        '/api/payments/status/$paymentId',
        queryParameters: qp.isEmpty ? null : qp,
        options: Options(
          validateStatus: (c) => c != null && c >= 200 && c < 500,
          responseType: ResponseType.json,
        ),
      );
      final data = r.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
    } on DioException catch (e) {
      if (kDebugMode) {
        AppLogger.error(
          'fetchPaymentStatus failed: ${e.message}',
          error: e,
          stackTrace: e.stackTrace,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        AppLogger.error('fetchPaymentStatus failed: $e', error: e);
      }
    }
    return null;
  }

  void _handleWebNetworkError(DioException e) => throwIfWebCorsOrNetwork(e);

  /// Maps [e] to [ApiException] (CORS on web, network, or server body message).
  Never _throwMappedApiException(DioException e) => throwMappedApiException(e);

  /// Transforms an image using AI with the selected theme.
  ///
  /// Returns the transformed image as a [TransformedImageModel].
  /// Throws [ApiException] if the transformation fails.
  Future<TransformedImageModel> transformImage({
    required XFile image,
    required ThemeModel theme,
    required String originalPhotoId,
  }) async {
    try {
      // Convert XFile to File for Retrofit (mobile) or use direct upload (web)
      dynamic
          tempFile; // Use dynamic to avoid type conflicts between dart:io and dart:html
      if (kIsWeb) {
        // On web, we need to create a temporary file-like object
        // Since Retrofit expects File, we'll use a workaround with Dio directly
        final imageBytes = await image.readAsBytes();
        final multipartFile = MultipartFile.fromBytes(
          imageBytes,
          filename: image.name,
        );

        // Use Dio directly for web since Retrofit doesn't support web File
        final dio = Dio(BaseOptions(
          baseUrl: AppConstants.kBaseUrl,
          connectTimeout: AppConstants.kApiTimeout,
          receiveTimeout: AppConstants.kApiTimeout,
          sendTimeout: AppConstants.kApiTimeout,
          headers: ClientIdentification.mergeHeaders({
            ...AppConfig.authorizationBearerHeader,
          }),
        ));
        if (kDebugMode == true) {
          dio.interceptors.add(ApiLoggingInterceptor());
          dio.interceptors.add(AliceDioProxyInterceptor());
        }

        // Configure browser adapter for web (critical for web platform)
        configureDioForWeb(dio);

        final formData = FormData.fromMap({
          'prompt': theme.promptText,
          'negative_prompt': theme.negativePrompt ?? '',
          'image': multipartFile,
        });

        final response = await dio.post<List<int>>(
          '/ai-transform',
          data: formData,
          options: Options(responseType: ResponseType.bytes),
        );

        final responseBytes = response.data ?? [];

        // Continue with responseBytes processing
        if (responseBytes.isEmpty) {
          throw ApiException('Received empty image data from API');
        }

        // Save transformed image as base64 data URL
        final base64String = base64Encode(responseBytes);
        final dataUrl = 'data:image/jpeg;base64,$base64String';

        return TransformedImageModel(
          id: _uuid.v4(),
          imageUrl: dataUrl,
          originalPhotoId: originalPhotoId,
          themeId: theme.id,
          transformedAt: DateTime.now(),
          runId: null,
        );
      } else {
        // On mobile, convert XFile to File for Retrofit
        final imageBytes = await image.readAsBytes();
        final tempDirPath = await FileHelper.getTempDirectoryPath();
        tempFile =
            FileHelper.createFile('$tempDirPath/upload_${_uuid.v4()}.jpg');
        await (tempFile as dynamic).writeAsBytes(imageBytes);

        // Call Retrofit API (mobile only - this code never executes on web)
        final responseBytes = await _apiClient.transformImage(
          theme.promptText,
          theme.negativePrompt ?? '',
          tempFile as dynamic, // Cast to dynamic to avoid type conflicts
        );

        // Clean up temp file (mobile only)
        if ((tempFile as dynamic).existsSync()) {
          await (tempFile as dynamic).delete();
        }

        // Validate that we received image data
        if (responseBytes.isEmpty) {
          throw ApiException('Received empty image data from API');
        }

        // Save transformed image to temp file and return path as URL
        final tempDirPath2 = await FileHelper.getTempDirectoryPath();
        final filePath = '$tempDirPath2/transformed_${_uuid.v4()}.jpg';
        final file = FileHelper.createFile(filePath);
        await (file as dynamic).writeAsBytes(responseBytes);

        // Verify the file was written correctly
        if (!(file as dynamic).existsSync()) {
          throw ApiException('Failed to save transformed image file');
        }

        final fileSize = await (file as dynamic).length();
        if (fileSize == 0) {
          throw ApiException('Saved image file is empty');
        }

        // For local file, use file:// URL format
        final localFileUrl = 'file://${(file as dynamic).path}';

        return TransformedImageModel(
          id: _uuid.v4(),
          imageUrl: localFileUrl,
          localFile: XFile((file as dynamic).path),
          originalPhotoId: originalPhotoId,
          themeId: theme.id,
          transformedAt: DateTime.now(),
          runId: null,
        );
      }
    } on DioException catch (e) {
      _throwMappedApiException(e);
    } catch (e) {
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException('${AppConstants.kErrorUnknown}: $e');
    }
  }

  /// Fetches available themes from the API
  /// Returns only themes where isActive is true
  Future<List<ThemeModel>> getThemes() async {
    try {
      // Kiosk-aware themes: pass kiosk identifiers when available.
      // Backend may ignore these params if not implemented; safe no-op.
      final kioskCode = (await KioskManager().getKioskCode())?.trim().toUpperCase();
      final kioskId = SessionManager().currentSession?.kioskId;

      final qp = <String, dynamic>{};
      if (kioskCode != null && kioskCode.isNotEmpty) {
        qp['kioskCode'] = kioskCode;
      }
      if (kioskId != null && kioskId.isNotEmpty) {
        qp['kioskId'] = kioskId;
      }

      final r = await _dio.get<dynamic>(
        '/api/themes',
        queryParameters: qp.isEmpty ? null : qp,
        options: Options(
          responseType: ResponseType.json,
        ),
      );

      final data = r.data;
      if (data is List) {
        return data
            .whereType<Map>()
            .map((e) => ThemeModel.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }

      throw ApiException('Unexpected themes response from API');
      // Filter themes where isActive is true
      // return themes.where((theme) => theme.isActive == true).toList();
    } on DioException catch (e) {
      // Check for CORS or network errors (common on web)
      if (kIsWeb &&
          (e.type == DioExceptionType.connectionError ||
              e.type == DioExceptionType.unknown)) {
        final errorMsg = e.message ?? '';
        if (errorMsg.contains('XMLHttpRequest') ||
            errorMsg.contains('CORS') ||
            errorMsg.contains(AppStrings.failedToFetch) ||
            errorMsg.contains('NetworkError')) {
          throw ApiException(
            'CORS Error: The API server at ${AppConstants.kBaseUrl} is not configured to allow requests from this origin. '
            'Please contact the server administrator to add CORS headers allowing requests from your domain. '
            'Error details: ${e.message ?? AppStrings.unknownNetworkError}',
          );
        }
      }

      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw ApiException(
            'Connection error occurred: ${e.message ?? AppConstants.kErrorNetwork}');
      }
      throw ApiException(
        'Failed to fetch themes: ${e.message}',
        e.response?.statusCode,
      );
    } catch (e) {
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException('Failed to fetch themes: $e');
    }
  }

  /// Validates a kiosk code by attempting a kiosk-filtered themes fetch.
  ///
  /// Returns true if the server returns at least one theme for that kiosk code.
  /// If the backend returns an error or an empty list, treat it as invalid/unprovisioned.
  Future<bool> validateKioskCode(String kioskCode) async {
    final code = kioskCode.trim().toUpperCase();
    if (code.isEmpty) return false;
    try {
      final r = await _dio.get<dynamic>(
        '/api/themes',
        queryParameters: {'kioskCode': code},
        options: Options(responseType: ResponseType.json),
      );
      final data = r.data;
      if (data is List) {
        return data.isNotEmpty;
      }
      return false;
    } on DioException catch (e) {
      _handleWebNetworkError(e);
      return false;
    } catch (_) {
      return false;
    }
  }

  /// GET `/api/kiosk/by-code/:code` — kiosk metadata used on initial URL bind.
  ///
  /// Returns `null` when the server rejects the code / not found.
  Future<KioskInfoModel?> fetchKioskByCode(String kioskCode) async {
    final code = kioskCode.trim().toUpperCase();
    if (code.isEmpty) return null;
    try {
      final r = await _dio.get<dynamic>(
        '/api/kiosk/by-code/$code',
        options: Options(
          responseType: ResponseType.json,
          validateStatus: (c) => c != null && c >= 200 && c < 500,
        ),
      );
      final data = r.data;
      if (r.statusCode != null && r.statusCode! >= 400) {
        return null;
      }
      if (data is Map<String, dynamic>) {
        final m = KioskInfoModel.fromJson(data);
        return m.isValid ? m : null;
      }
      if (data is Map) {
        final m = KioskInfoModel.fromJson(Map<String, dynamic>.from(data));
        return m.isValid ? m : null;
      }
    } on DioException catch (e) {
      _handleWebNetworkError(e);
    } catch (_) {}
    return null;
  }

  /// Parses JSON from `GET /api/kiosk/frames`. Throws [ApiException] if the payload
  /// is not a list or `{ "frames" | "data": [...] }`, or if an entry is invalid.
  List<KioskFrameModel> _parseKioskFramesBody(dynamic data) {
    if (data == null) {
      return <KioskFrameModel>[];
    }
    final List<dynamic> raw;
    if (data is List) {
      raw = data;
    } else if (data is Map &&
        (data['frames'] is List || data['data'] is List)) {
      raw = (data['frames'] ?? data['data']) as List<dynamic>;
    } else {
      throw ApiException('Unexpected frames response from API');
    }
    return raw
        .map((e) {
          if (e is! Map) {
            throw ApiException('Invalid frame entry in API response');
          }
          return KioskFrameModel.fromJson(Map<String, dynamic>.from(e));
        })
        .where((f) => f.id.isNotEmpty && f.overlayUrl.isNotEmpty)
        .toList();
  }

  /// GET `/api/kiosk/frames` — active occasion frames for the current kiosk session.
  ///
  /// Backend requires at least one of `kioskCode` or `kioskId` (same as themes).
  Future<List<KioskFrameModel>> getKioskFrames() async {
    try {
      final kioskCode =
          (await KioskManager().getKioskCode())?.trim().toUpperCase();
      final kioskId = SessionManager().currentSession?.kioskId;

      final qp = <String, dynamic>{};
      if (kioskCode != null && kioskCode.isNotEmpty) {
        qp['kioskCode'] = kioskCode;
      }
      if (kioskId != null && kioskId.isNotEmpty) {
        qp['kioskId'] = kioskId;
      }
      if (qp.isEmpty) {
        throw ApiException(
          'Kiosk code or kiosk id is required to load frames. '
          'Link a kiosk in settings, then try again.',
        );
      }

      final r = await _dio.get<dynamic>(
        '/api/kiosk/frames',
        queryParameters: qp,
        options: Options(
          responseType: ResponseType.json,
          // Include 5xx so we can handle misconfigured APIs that error instead of
          // returning 200 + `[]` when a kiosk has no occasion frames.
          validateStatus: (c) => c != null && c < 600,
        ),
      );
      final data = r.data;
      final status = r.statusCode ?? 200;

      if (status >= 500) {
        try {
          return _parseKioskFramesBody(data);
        } catch (e, st) {
          AppLogger.warning(
            'GET /api/kiosk/frames returned HTTP $status; treating as no frames. '
            'Prefer returning 200 with an empty list when none are configured.',
            error: e,
            stackTrace: st,
          );
          return <KioskFrameModel>[];
        }
      }

      if (status >= 400) {
        if (data is Map<String, dynamic>) {
          throw ApiException(
            data['error']?.toString() ??
                data['message']?.toString() ??
                'Failed to load frames ($status)',
            status,
          );
        }
        throw ApiException('Failed to load frames ($status)', status);
      }

      return _parseKioskFramesBody(data);
    } on ApiException {
      rethrow;
    } on DioException catch (e) {
      _handleWebNetworkError(e);
      throw ApiException(
        'Failed to load frames: ${e.message}',
        e.response?.statusCode,
      );
    }
  }

  /// Accepts terms and conditions (legacy)
  Future<void> acceptTerms({required String deviceType}) async {
    try {
      await _apiClient.acceptTerms({
        'device_type': deviceType,
        'accepted': true,
      });
    } on DioException catch (e) {
      _throwMappedApiException(e);
    } catch (e) {
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException('${AppConstants.kErrorUnknown}: $e');
    }
  }

  /// Fetches app settings from API.
  Future<AppSettingsModel> getAppSettings() async {
    try {
      return await _apiClient.getAppSettings();
    } on DioException catch (e) {
      _throwMappedApiException(e);
    } catch (e) {
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException('${AppConstants.kErrorUnknown}: $e');
    }
  }

  /// Accepts terms and creates a new session
  /// Returns session data including sessionId
  Future<Map<String, dynamic>> acceptTermsAndCreateSession({
    String? kioskCode,
    String? source,
    String? selectedFrameId,
    bool includeSelectedFrameId = false,
  }) async {
    try {
      final response = await _apiClient.acceptTermsAndCreateSession({
        if (kioskCode != null && kioskCode.isNotEmpty) 'kioskCode': kioskCode,
        if (source != null && source.isNotEmpty) 'source': source,
        if (includeSelectedFrameId) 'selectedFrameId': selectedFrameId,
      });
      return response;
    } on DioException catch (e) {
      _throwMappedApiException(e);
    } catch (e) {
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException('${AppConstants.kErrorUnknown}: $e');
    }
  }

  /// PATCH `/api/sessions/{sessionId}` — session updates used across the flow:
  /// 1. Photo: body includes `userImageUrl` (data URL) — step after capture.
  /// 2. Theme: body includes `selectedThemeId` — after theme selection.
  /// 3. Frame: `includeSelectedFrameId` + `selectedFrameId` when applicable.
  ///
  /// Server contract (no separate upload-photo route): photo is always this PATCH.
  /// Returns parsed session JSON. At least one of `userImageUrl`, `selectedThemeId`,
  /// or `selectedFrameId` (with `includeSelectedFrameId`) must be provided.
  Future<Map<String, dynamic>> updateSession({
    required String sessionId,
    String? userImageUrl, // Base64 data URL (optional)
    String? selectedThemeId, // Optional - can be set later
    /// When true, sends `selectedFrameId` in the body (value may be JSON `null`).
    bool includeSelectedFrameId = false,
    String? selectedFrameId,
    /// Optional face count hint when sending `userImageUrl`.
    int? personCount,
    /// Optional framing metadata (recommended with photo upload).
    Map<String, dynamic>? framingMetadata,
  }) async {
    try {
      final body = <String, dynamic>{};

      if (userImageUrl != null) {
        body['userImageUrl'] = userImageUrl;
      }
      if (selectedThemeId != null) {
        body['selectedThemeId'] = selectedThemeId;
      }
      if (includeSelectedFrameId) {
        body['selectedFrameId'] = selectedFrameId;
      }
      if (personCount != null) {
        body['personCount'] = personCount;
      }
      if (framingMetadata != null && framingMetadata.isNotEmpty) {
        body['framingMetadata'] = framingMetadata;
      }

      if (userImageUrl != null) {
        SessionUserImageValidation.assertValidForSessionPatch(userImageUrl);
      }

      // Ensure at least one field is provided
      if (body.isEmpty) {
        throw ApiException(
            'At least one of userImageUrl, selectedThemeId, or selectedFrameId '
            '(with includeSelectedFrameId) must be provided');
      }

      // Plain text + [compute] so a multi‑MB echoed `userImageUrl` is not jsonDecoded
      // on the UI thread (was freezing Chrome right after PATCH 200).
      final httpResponse = await _dio.patch<String>(
        '/api/sessions/$sessionId',
        data: body,
        options: Options(
          contentType: Headers.jsonContentType,
          responseType: ResponseType.plain,
        ),
      );

      final text = httpResponse.data;
      if (text == null || text.isEmpty) {
        throw ApiException('Empty session response');
      }
      // Web: [compute] does not use a worker — strip huge fields first, then decode here.
      if (kIsWeb) {
        return _parseSessionPatchResponseJson(text);
      }
      return await compute(_parseSessionPatchResponseJson, text);
    } on DioException catch (e) {
      _handleWebNetworkError(e);

      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw ApiException(AppConstants.kErrorNetwork);
      }

      _throwMappedApiException(e);
    } catch (e) {
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException('${AppConstants.kErrorUnknown}: $e');
    }
  }

  /// Deletes the session and associated data on the server
  /// DELETE /api/sessions/{sessionId}
  Future<void> deleteSession(String sessionId) async {
    try {
      await _apiClient.deleteSession(sessionId);
    } on DioException catch (e) {
      _throwMappedApiException(e);
    } catch (e) {
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException('${AppConstants.kErrorUnknown}: $e');
    }
  }

  /// GET `/api/sessions/{sessionId}` — used to poll approval state when gateway is disabled.
  Future<Map<String, dynamic>?> fetchSession(String sessionId) async {
    if (sessionId.trim().isEmpty) return null;
    try {
      final raw = await _apiClient.getSession(sessionId.trim());
      if (raw is Map<String, dynamic>) return raw;
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } on DioException catch (e) {
      _handleWebNetworkError(e);
      if (kDebugMode) {
        AppLogger.error(
          'fetchSession failed: ${e.message}',
          error: e,
          stackTrace: e.stackTrace,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        AppLogger.error('fetchSession failed: $e', error: e);
      }
    }
    return null;
  }

  /// GET `/api/generation-runs/:runId` — transformation run + steps (kiosk forensics UI).
  Future<Map<String, dynamic>> fetchGenerationRun(String runId) async {
    final id = runId.trim();
    if (id.isEmpty) {
      throw ApiException('runId is required');
    }
    try {
      final r = await _dio.get<dynamic>('/api/generation-runs/$id');
      final data = r.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      throw ApiException('Unexpected generation run response');
    } on DioException catch (e) {
      _throwMappedApiException(e);
    } catch (e) {
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException('${AppConstants.kErrorUnknown}: $e');
    }
  }

  /// POST /api/payment/initiate — returns payment link for UPI QR.
  Future<PaymentInitiateResult> initiatePayment({
    required String sessionId,
    required int amount,
    String type = 'INITIAL',
    String? customerPhone,
    required String fcmToken,
  }) async {
    try {
      final body = <String, dynamic>{
        'sessionId': sessionId,
        'amount': amount,
        'type': type,
        'fcmToken': fcmToken,
      };
      if (customerPhone != null && customerPhone.trim().isNotEmpty) {
        body['customerPhone'] = customerPhone.trim();
      }

      final raw = await _apiClient.initiatePayment(body);
      if (raw is! Map) {
        throw ApiException(
          '${AppConstants.kErrorApiCall}: unexpected payment response',
        );
      }
      final rawMap = Map<String, dynamic>.from(raw);
      return PaymentInitiateResult.fromJson(rawMap);
    } on DioException catch (e) {
      _throwMappedApiException(e);
    } catch (e) {
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException('${AppConstants.kErrorUnknown}: $e');
    }
  }

  /// Generates transformed image using AI
  /// This call can take 10-60+ seconds, with a 180-second (3 minute) timeout
  /// Retries once on timeout before showing error
  /// Returns TransformedImageModel with the image URL (no download)
  Future<TransformedImageModel> generateImage({
    required String sessionId,
    required int attempt,
    required String originalPhotoId,
    required String themeId,
    void Function(String message)? onProgress,
  }) async {
    // Create a Dio instance with extended timeout for AI generation
    // AI generation can take 10-60+ seconds depending on server load
    final dioWithTimeout = Dio(
      BaseOptions(
        baseUrl: AppConstants.kBaseUrl,
        connectTimeout: AppConstants.kAiGenerationTimeout,
        receiveTimeout: AppConstants.kAiGenerationTimeout,
        sendTimeout: AppConstants.kAiGenerationTimeout,
        headers: ClientIdentification.mergeHeaders({
          'Content-Type': 'application/json',
          ...AppConfig.authorizationBearerHeader,
        }),
      ),
    );

    // Configure browser adapter for web (important for all Dio instances)
    configureDioForWeb(dioWithTimeout);

    if (kDebugMode == true) {
      dioWithTimeout.interceptors.add(ApiLoggingInterceptor());
      dioWithTimeout.interceptors.add(AliceDioProxyInterceptor());
    }

    final apiClientWithTimeout =
        ApiClient(dioWithTimeout, baseUrl: AppConstants.kBaseUrl);

    // Retry logic: try once, retry once on timeout
    int retryCount = 0;
    const maxRetries = 1;

    while (retryCount <= maxRetries) {
      try {
        // Server reads source image from the session (after PATCH photo + PATCH theme).
        // [originalPhotoId] / [themeId] are for client-side [TransformedImageModel] only.
        final response = await apiClientWithTimeout.generateImage({
          'sessionId': sessionId,
          'attempt': attempt,
          'trackDetails': true,
        });
        onProgress?.call('Response received');

        // Validate response
        if (response['success'] != true) {
          final errorMsg = response['error'] as String? ?? 'Generation failed';
          throw ApiException(errorMsg);
        }

        final imageUrl = response['imageUrl'] as String?;
        if (imageUrl == null || imageUrl.isEmpty) {
          throw ApiException('No image URL in response');
        }

        // Log additional response metadata (optional, for debugging/analytics)
        final runId = response['runId'] as String?;
        final framing = response['framing'] as Map<String, dynamic>?;
        final timing = response['timing'] as Map<String, dynamic>?;
        final faceVerification =
            response['faceVerification'] as Map<String, dynamic>?;
        final evaluation = response['evaluation'] as Map<String, dynamic>?;

        if (runId != null || framing != null || timing != null) {
          AppLogger.debug('📊 Generation metadata:');
          if (runId != null) {
            AppLogger.debug('   Run ID: $runId');
          }
          if (framing != null) {
            AppLogger.debug(
                '   Framing: ${framing['personCount']} person(s), ${framing['orientation']}, ${framing['zoomLevel']}, ${framing['aspectRatio']}');
          }
          if (timing != null) {
            final totalMs = timing['totalMs'] as int?;
            final generationMs = timing['generationMs'] as int?;
            final upscaleMs = timing['upscaleMs'] as int?;
            if (totalMs != null) {
              AppLogger.debug('   Total duration: ${totalMs}ms');
              if (generationMs != null) {
                AppLogger.debug('   Generation: ${generationMs}ms');
              }
              if (upscaleMs != null && upscaleMs > 0) {
                AppLogger.debug('   Upscale: ${upscaleMs}ms');
              }
            }
          }
          if (faceVerification != null) {
            AppLogger.debug(
                '   Face verification: ${faceVerification['originalCount']} original, ${faceVerification['generatedCount']} generated, match: ${faceVerification['match']}');
          }
          if (evaluation != null) {
            AppLogger.debug(
                '   Evaluation: composite=${evaluation['compositeScore']}, identity=${evaluation['identityScore']}, prompt=${evaluation['promptScore']}');
          }
        }

        // Backend may return a relative path (e.g. `/api/img/generated/...`); resolve
        // against [AppConstants.kBaseUrl] so [NetworkImage] / Dio always get an absolute URI.
        final resolvedImageUrl = _resolveImageUrl(imageUrl);

        // Just return the URL - no XFile wrapper, no download
        return TransformedImageModel(
          id: _uuid.v4(),
          imageUrl: resolvedImageUrl,
          originalPhotoId: originalPhotoId,
          themeId: themeId,
          transformedAt: DateTime.now(),
          runId: runId,
        );
      } on DioException catch (e) {
        final isTimeout = e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout;

        if (isTimeout && retryCount < maxRetries) {
          retryCount++;
          continue;
        }

        GenerationApiFailure.fromDioException(e).rethrowAsApiException();
      } catch (e) {
        if (e is ApiException) {
          rethrow;
        }
        throw ApiException('Failed to generate image: $e');
      }
    }

    // This should never be reached, but just in case
    throw ApiException('Failed to generate image after retries');
  }

  /// Server-aligned generation: **count == 1** → POST `/api/generate-image`;
  /// **count > 1** → GET `/api/generate-stream-parallel?count=…` (SSE).
  ///
  /// Pass [count] from `/api/settings` `parallelImageCount` (via [AppSettingsManager.resolveParallelImageCount]).
  /// [attempt] is only used for the POST path (1-based generation attempt for the session).
  Future<ParallelGenerationResult> generateImages({
    required String sessionId,
    required int count,
    required int attempt,
    required String originalPhotoId,
    required String themeId,
    void Function(String message)? onProgress,
    void Function(String eventType, Map<String, dynamic> json)? onSseEvent,
  }) async {
    final n = count < 1 ? 1 : count;
    if (n == 1) {
      final m = await generateImage(
        sessionId: sessionId,
        attempt: attempt,
        originalPhotoId: originalPhotoId,
        themeId: themeId,
        onProgress: onProgress,
      );
      return ParallelGenerationResult(
        imageUrlsBySlot: [m.imageUrl],
        runId: m.runId,
      );
    }
    return generateImageParallelStream(
      sessionId: sessionId,
      count: n,
      originalPhotoId: originalPhotoId,
      themeId: themeId,
      onProgress: onProgress,
      onSseEvent: onSseEvent,
    );
  }

  /// Parallel AI generation via GET `/api/generate-stream-parallel` (SSE).
  ///
  /// See product doc: "Parallel Generation with SSE". Uses [sessionId] and [count];
  /// [originalPhotoId] and [themeId] are accepted for parity with [generateImage] (logging only).
  ///
  /// The legacy [generateImage] (POST `/api/generate-image`) remains available if needed later.
  Future<ParallelGenerationResult> generateImageParallelStream({
    required String sessionId,
    int count = AppConstants.kAiParallelGenerationCount,
    required String originalPhotoId,
    required String themeId,
    void Function(String message)? onProgress,
    void Function(String eventType, Map<String, dynamic> json)? onSseEvent,
  }) async {
    AppLogger.debug(
        '📡 Parallel SSE generation session=$sessionId photo=$originalPhotoId theme=$themeId count=$count');

    final dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.kBaseUrl,
        connectTimeout: AppConstants.kApiTimeout,
        receiveTimeout: AppConstants.kAiGenerationTimeout,
        sendTimeout: AppConstants.kAiGenerationTimeout,
        headers: ClientIdentification.mergeHeaders({
          'Accept': 'text/event-stream',
          ...AppConfig.authorizationBearerHeader,
        }),
      ),
    );

    configureDioForWeb(dio);

    if (kDebugMode == true) {
      dio.interceptors.add(ApiLoggingInterceptor());
      dio.interceptors.add(AliceDioProxyInterceptor());
    }

    final slots = List<String>.filled(count, '');
    final qualityByIndex = <int, double>{};
    final completer = Completer<ParallelGenerationResult>();

    try {
      final response = await dio.get(
        '/api/generate-stream-parallel',
        queryParameters: {
          'sessionId': sessionId,
          'count': count,
        },
        options: Options(
          responseType: ResponseType.stream,
        ),
      );

      final body = response.data;
      if (body is! ResponseBody) {
        throw ApiException('Unexpected response for parallel generation stream');
      }

      final buffer = StringBuffer();
      try {
        await for (final chunk in utf8.decoder.bind(body.stream)) {
          buffer.write(chunk);
          while (true) {
            final current = buffer.toString();
            final sep = current.indexOf('\n\n');
            if (sep < 0) break;
            var block = current.substring(0, sep);
            final remaining = current.substring(sep + 2);
            buffer
              ..clear()
              ..write(remaining);
            if (block.endsWith('\r')) {
              block = block.substring(0, block.length - 1);
            }
            _dispatchParallelSseBlock(
              block,
              slots: slots,
              qualityByIndex: qualityByIndex,
              completer: completer,
              onProgress: onProgress,
              onSseEvent: onSseEvent,
            );
            if (completer.isCompleted) {
              return await completer.future;
            }
          }
        }
        final remaining = buffer.toString();
        if (remaining.trim().isNotEmpty) {
          _dispatchParallelSseBlock(
            remaining,
            slots: slots,
            qualityByIndex: qualityByIndex,
            completer: completer,
            onProgress: onProgress,
            onSseEvent: onSseEvent,
          );
        }
      } catch (e) {
        if (!completer.isCompleted) {
          completer.completeError(
            ApiException('Parallel generation stream failed: $e'),
          );
        }
      }

      if (!completer.isCompleted) {
        if (slots.any((u) => u.isNotEmpty)) {
          completer.complete(
            ParallelGenerationResult(
              imageUrlsBySlot: List<String>.from(slots),
              success: true,
              qualityScoreByIndex: Map<int, double>.from(qualityByIndex),
            ),
          );
        } else {
          completer.completeError(
            ApiException('Generation ended without any image'),
          );
        }
      }

      return await completer.future;
    } on DioException catch (e) {
      _throwMappedApiException(e);
    }
  }

  Future<XFile> downloadImageToTemp(
    String imageUrl, {
    void Function(String message)? onProgress,
  }) async {
    if (kIsWeb) {
      return XFile(imageUrl);
    }

    final resolvedUrl = _withSessionIdIfMissing(_resolveImageUrl(imageUrl));

    // Use the app's authenticated Dio instance (some image endpoints are protected and
    // can return 403 without auth headers). Override timeouts for large downloads.
    final dio = _dio;
    final previousConnectTimeout = dio.options.connectTimeout;
    final previousReceiveTimeout = dio.options.receiveTimeout;
    dio.options = dio.options.copyWith(
      connectTimeout: AppConstants.kAiGenerationTimeout,
      receiveTimeout: AppConstants.kAiGenerationTimeout,
    );

    AppLogger.debug('📥 Downloading image from: $resolvedUrl');
    final extension = resolvedUrl.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final tempDirPath = await FileHelper.getTempDirectoryPath();
    final fileName = 'transformed_${_uuid.v4()}.$extension';
    final filePath = '$tempDirPath/$fileName';
    final file = FileHelper.createFile(filePath);

    onProgress?.call('Downloading result...');
    int lastReportedPercent = -1;
    Future<void> attemptDownload({required Map<String, dynamic>? headers}) async {
      await dio.download(
        resolvedUrl,
        (file as dynamic).path,
        onReceiveProgress: (received, total) {
          if (total <= 0) {
            return;
          }
          final percent = ((received / total) * 100).floor();
          if (percent >= lastReportedPercent + 5 || percent == 100) {
            lastReportedPercent = percent;
            onProgress?.call('Downloading result... $percent%');
          }
        },
        options: Options(headers: headers),
        deleteOnError: true,
      );
    }

    try {
      // First attempt: authenticated headers (some endpoints require this).
      await attemptDownload(headers: dio.options.headers);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      AppLogger.error(
        'Image download failed ($status) for $resolvedUrl: $body',
        error: e,
        stackTrace: e.stackTrace,
      );

      // Some image/CDN endpoints reject bearer headers and respond with 403.
      // Retry once without Authorization before surfacing the error.
      if (status == 403) {
        try {
          final unauthHeaders = Map<String, dynamic>.from(dio.options.headers);
          unauthHeaders.remove('Authorization');
          unauthHeaders.remove('authorization');
          lastReportedPercent = -1;
          onProgress?.call('Retrying download...');
          try {
            if ((file as dynamic).existsSync()) {
              await (file as dynamic).delete();
            }
          } catch (_) {}
          await attemptDownload(headers: unauthHeaders);
          return XFile((file as dynamic).path);
        } on DioException catch (retry) {
          final rStatus = retry.response?.statusCode;
          final rBody = retry.response?.data;
          AppLogger.debug(
            '❌ Image download retry (no auth) failed ($rStatus) for $resolvedUrl: $rBody',
          );
          throw ApiException(
            'Failed to download image (${rStatus ?? status ?? "unknown"}): ${rBody ?? body ?? retry.message ?? retry}\nURL: $resolvedUrl',
            rStatus ?? status,
          );
        }
      }

      throw ApiException(
        'Failed to download image (${status ?? "unknown"}): ${body ?? e.message ?? e}\nURL: $resolvedUrl',
        status,
      );
    } finally {
      // Restore global timeouts so other requests keep their intended behavior.
      dio.options = dio.options.copyWith(
        connectTimeout: previousConnectTimeout,
        receiveTimeout: previousReceiveTimeout,
      );
    }

    // Verify the file was written correctly
    if (!(file as dynamic).existsSync()) {
      throw ApiException('Failed to save transformed image file at: $filePath');
    }

    final fileSize = await (file as dynamic).length();
    if (fileSize == 0) {
      throw ApiException('Saved image file is empty at: $filePath');
    }

    final savedPath = (file as dynamic).path;
    AppLogger.debug('✅ Saved transformed image: $savedPath ($fileSize bytes)');
    return XFile(savedPath);
  }

  /// Ensures URLs returned by the backend can be used by Dio.
  ///
  /// Backend may return relative paths like `/api/img/generated/...jpg` (or
  /// occasionally paths with whitespace/newlines). Dio requires an absolute URI.
  static String _resolveImageUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;

    // Remove any whitespace/newlines accidentally included in the URL.
    final compact = trimmed.replaceAll(RegExp(r'\s+'), '');

    if (compact.startsWith('http://') || compact.startsWith('https://')) {
      return compact;
    }

    // Treat as relative to API base.
    final base = Uri.parse(AppConstants.kBaseUrl);
    // Uri.resolve handles leading slashes correctly.
    return base.resolve(compact).toString();
  }

  /// Adds session context for protected image endpoints when needed.
  ///
  /// Some backends protect generated images and require `sessionId` as a query param
  /// (in addition to, or instead of, bearer auth). This keeps the client compatible
  /// with both public and signed/protected URL modes.
  static String _withSessionIdIfMissing(String url) {
    final sessionId = SessionManager().sessionId;
    if (sessionId == null || sessionId.isEmpty) return url;

    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    if (!uri.path.startsWith('/api/img/generated/')) return url;
    if (uri.queryParameters.containsKey('sessionId')) return url;

    final qp = Map<String, String>.from(uri.queryParameters);
    qp['sessionId'] = sessionId;
    return uri.replace(queryParameters: qp).toString();
  }

  /// Preprocesses image (validation, compression, person detection)
  /// This is a fire-and-forget call - errors are silently ignored
  /// Should be called immediately after uploading photo to save 2-3 seconds during AI generation
  void preprocessImage({
    required String sessionId,
    int? clientFaceCount,
  }) {
    // Fire-and-forget: don't await, don't handle errors
    // If preprocessing fails, the generate endpoint will handle it automatically
    final body = <String, dynamic>{
      'sessionId': sessionId,
      if (clientFaceCount != null) 'clientFaceCount': clientFaceCount,
    };
    _apiClient.preprocessImage(body).then((_) {
      // Success - preprocessing completed
      AppLogger.debug('✅ Preprocess image completed');
    }).catchError((error) {
      // Silently ignore errors - this is a background optimization
      AppLogger.error('Preprocess image failed (non-critical): $error', error: error);
    });
  }
}

void _dispatchParallelSseBlock(
  String block, {
  required List<String> slots,
  required Map<int, double> qualityByIndex,
  required Completer<ParallelGenerationResult> completer,
  void Function(String message)? onProgress,
  void Function(String eventType, Map<String, dynamic> json)? onSseEvent,
}) {
  String? eventType;
  final dataParts = <String>[];
  for (final rawLine in block.split('\n')) {
    final line = rawLine.trimRight();
    if (line.isEmpty) continue;
    if (line.startsWith('event:')) {
      eventType = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      dataParts.add(line.substring(5).trimLeft());
    }
  }
  if (dataParts.isEmpty) return;

  final payload = dataParts.join('\n');
  final Map<String, dynamic> json;
  try {
    json = jsonDecode(payload) as Map<String, dynamic>;
  } catch (_) {
    return;
  }

  final et = (eventType ?? '').trim();
  if (et.isNotEmpty) {
    onSseEvent?.call(et, json);
  }

  switch (et) {
    case 'status':
      final total = json['imageCount'] ?? json['total'];
      onProgress?.call(
        total != null
            ? 'Starting generation ($total options)...'
            : 'Starting generation...',
      );
      break;
    case 'start':
      final total = json['total'];
      onProgress?.call(
        total != null
            ? 'Starting parallel generation ($total options)...'
            : 'Starting parallel generation...',
      );
      break;
    case 'step':
      final step = json['step'] as String?;
      final st = json['status'] as String?;
      if (step != null && st == 'active') {
        onProgress?.call('Step: $step');
      }
      break;
    case 'attempt_start':
      final a = json['attempt'];
      final ta = json['totalAttempts'];
      if (a != null && ta != null) {
        onProgress?.call('Attempt $a of $ta...');
      }
      break;
    case 'attempt_complete':
      final sc = json['score'];
      if (sc != null) {
        onProgress?.call('Quality score: $sc');
      }
      break;
    case 'commentary':
      final m = json['message'] as String?;
      if (m != null && m.isNotEmpty) {
        onProgress?.call(m);
      }
      break;
    case 'commentary_clear':
      break;
    case 'warning':
      final w = json['message'] as String?;
      if (w != null && w.isNotEmpty) {
        onProgress?.call('Warning: $w');
      }
      break;
    case 'image_complete':
      int? idx;
      final rawIdx = json['index'];
      if (rawIdx is int) {
        idx = rawIdx;
      } else if (rawIdx is num) {
        idx = rawIdx.toInt();
      }
      final url = json['imageUrl'] as String?;
      final q = json['qualityScore'];
      if (idx != null &&
          idx >= 0 &&
          idx < slots.length &&
          url != null &&
          url.isNotEmpty) {
        slots[idx] = ApiService._resolveImageUrl(url);
        if (q is num) {
          qualityByIndex[idx] = q.toDouble();
        }
        final c = json['completed'];
        final t = json['total'];
        if (c != null && t != null) {
          onProgress?.call('Option $c of $t ready...');
        } else {
          onProgress?.call('An option finished...');
        }
      }
      break;
    case 'image_failed':
      onProgress?.call('One option failed, continuing...');
      break;
    case 'complete':
      final urls = json['imageUrls'];
      if (urls is List) {
        for (var i = 0; i < urls.length && i < slots.length; i++) {
          final u = urls[i];
          if (u is String && u.isNotEmpty) {
            slots[i] = ApiService._resolveImageUrl(u);
          }
        }
      }
      final timing = json['timing'] as Map<String, dynamic>?;
      int? totalMs;
      final rawMs = timing?['totalMs'];
      if (rawMs is int) {
        totalMs = rawMs;
      } else if (rawMs is num) {
        totalMs = rawMs.toInt();
      }
      final runId = json['runId'] as String?;
      final selRaw = json['selectedIndex'];
      int? selectedIndex;
      if (selRaw is int) {
        selectedIndex = selRaw;
      } else if (selRaw is num) {
        selectedIndex = selRaw.toInt();
      }
      if (!completer.isCompleted) {
        completer.complete(
          ParallelGenerationResult(
            imageUrlsBySlot: List<String>.from(slots),
            success: json['success'] == true,
            timingTotalMs: totalMs,
            qualityScoreByIndex: Map<int, double>.from(qualityByIndex),
            runId: runId,
            selectedIndex: selectedIndex,
          ),
        );
      }
      break;
    case 'failure':
    case 'error':
      final msg = json['error'] as String? ??
          json['message'] as String? ??
          'Generation failed';
      if (!completer.isCompleted) {
        completer.completeError(ApiException(msg));
      }
      break;
    default:
      break;
  }
}
