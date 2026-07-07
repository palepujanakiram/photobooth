import 'dart:async';
import 'package:dio/dio.dart';
import 'package:camera/camera.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:uuid/uuid.dart';
import '../models/app_settings_model.dart';
import '../models/kiosk_frame_model.dart';
import '../models/kiosk_info_model.dart';
import '../models/payment_initiate_result.dart';
import '../models/preprocess_image_result.dart';
import '../models/parallel_generation_result.dart';
import '../screens/result/transformed_image_model.dart';
import '../screens/theme_selection/theme_model.dart';
import '../utils/exceptions.dart';
import '../utils/constants.dart';
import '../utils/session_user_image_validation.dart';
import '../utils/logger.dart';
import '../utils/web_flow_trace.dart';
import 'api_client.dart';
import 'api_service_dio.dart';
import 'client_identification.dart';
import 'api_dio_errors.dart';
import 'api_http_response.dart';
import 'generation_api_errors.dart';
import 'kiosk_manager.dart';
import 'session_manager.dart';
import 'api_service_legacy_media.dart';
import 'api_parallel_sse_consumer.dart';
import 'api_service_helpers.dart';
import 'api_service_web_session_patch_stub.dart'
    if (dart.library.html) 'api_service_web_session_patch_browser.dart';

class ApiService {
  late final ApiClient _apiClient;
  late final Dio _dio;
  late final Dio _aiDio;
  final Uuid _uuid = const Uuid();

  ApiService({Dio? dio, Dio? aiDio}) {
    _dio = dio ?? createProductionApiDio();
    _aiDio = aiDio ?? (dio ?? createAiGenerationDio());
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

  /// Legacy direct `/ai-transform` upload (unused by current kiosk flow).
  Future<TransformedImageModel> transformImage({
    required XFile image,
    required ThemeModel theme,
    required String originalPhotoId,
  }) =>
      ApiServiceLegacyMedia.transformImage(
        apiClient: _apiClient,
        uuid: _uuid,
        image: image,
        theme: theme,
        originalPhotoId: originalPhotoId,
      );

  /// Fetches available themes from the API
  /// Returns only themes where isActive is true
  Future<List<ThemeModel>> getThemes() async {
    try {
      final qp = await kioskThemesQueryParameters();
      final r = await _dio.get<dynamic>(
        '/api/themes',
        queryParameters: qp.isEmpty ? null : qp,
        options: Options(responseType: ResponseType.json),
      );
      return parseThemesResponseBody(r.data);
    } on DioException catch (e) {
      rethrowThemesFetchDioError(e);
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

  /// GET `/api/kiosk/generation-timing` — rolling p50/p90 for wait-screen ETAs.
  Future<Map<String, dynamic>> fetchKioskGenerationTiming() async {
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
          'Kiosk code or kiosk id is required to load generation timing.',
        );
      }

      final r = await _dio.get<dynamic>(
        '/api/kiosk/generation-timing',
        queryParameters: qp,
        options: Options(responseType: ResponseType.json),
      );
      final data = r.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      throw ApiException('Unexpected generation timing response');
    } on ApiException {
      rethrow;
    } on DioException catch (e) {
      _handleWebNetworkError(e);
      throw ApiException(
        'Failed to load generation timing: ${e.message}',
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
    bool groupConsentAccepted = true,
  }) async {
    try {
      final response = await _apiClient.acceptTermsAndCreateSession({
        if (kioskCode != null && kioskCode.isNotEmpty) 'kioskCode': kioskCode,
        if (source != null && source.isNotEmpty) 'source': source,
        'groupConsentAccepted': groupConsentAccepted,
        if (includeSelectedFrameId) 'selectedFrameId': selectedFrameId,
      });
      if (response is Map<String, dynamic>) return response;
      if (response is Map) return Map<String, dynamic>.from(response);
      throw ApiException('Unexpected session create response from API');
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
      if (userImageUrl != null) {
        SessionUserImageValidation.assertValidForSessionPatch(userImageUrl);
      }
      final body = buildSessionPatchBody(
        userImageUrl: userImageUrl,
        selectedThemeId: selectedThemeId,
        includeSelectedFrameId: includeSelectedFrameId,
        selectedFrameId: selectedFrameId,
        personCount: personCount,
        framingMetadata: framingMetadata,
      );

      final patchOptions = Options(
        contentType: Headers.jsonContentType,
        responseType: ResponseType.plain,
        sendTimeout: AppConstants.kSessionUploadTimeout,
        receiveTimeout: AppConstants.kSessionUploadTimeout,
      );

      final Response<String> httpResponse;
      if (kIsWeb && userImageUrl != null) {
        WebFlowTrace.log(
          'PATCH_API',
          'jsonEncode_start dataUrlChars=${userImageUrl.length}',
        );
        await Future<void>.delayed(Duration.zero);
        final encodeSw = Stopwatch()..start();
        final jsonBody = jsonEncode(body);
        WebFlowTrace.log(
          'PATCH_API',
          'jsonEncode_done ms=${encodeSw.elapsedMilliseconds} jsonChars=${jsonBody.length}',
        );
        await Future<void>.delayed(Duration.zero);
        final responseText = await patchSessionPhotoBodyOnWeb(
          sessionId: sessionId,
          jsonBody: jsonBody,
          timeout: AppConstants.kSessionUploadTimeout,
        );
        httpResponse = Response<String>(
          requestOptions: RequestOptions(path: '/api/sessions/$sessionId'),
          data: responseText,
          statusCode: 200,
        );
      } else {
        httpResponse = await _dio.patch<String>(
          '/api/sessions/$sessionId',
          data: body,
          options: patchOptions,
        );
      }

      await Future<void>.delayed(Duration.zero);
      WebFlowTrace.log('PATCH_API', 'decode_response_start');
      final decoded =
          await decodeSessionPatchResponseText(httpResponse.data ?? '');
      WebFlowTrace.log('PATCH_API', 'decode_response_done');
      return decoded;
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

    final apiClientWithTimeout =
        ApiClient(_aiDio, baseUrl: AppConstants.kBaseUrl);

    // Retry logic: try once, retry once on timeout
    int retryCount = 0;
    const maxRetries = 1;

    while (retryCount <= maxRetries) {
      try {
        return await generateTransformedImageOnce(
          apiClient: apiClientWithTimeout,
          sessionId: sessionId,
          attempt: attempt,
          originalPhotoId: originalPhotoId,
          themeId: themeId,
          uuid: _uuid,
          onProgress: onProgress,
        );
      } on DioException catch (e) {
        if (isGenerateImageDioTimeout(e) && retryCount < maxRetries) {
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

    try {
      final response = await _aiDio.get(
        '/api/generate-stream-parallel',
        queryParameters: {
          'sessionId': sessionId,
          'count': count,
        },
        options: Options(
          responseType: ResponseType.stream,
          headers: ClientIdentification.mergeHeaders({
            'Accept': 'text/event-stream',
          }),
        ),
      );

      final body = response.data;
      if (body is! ResponseBody) {
        throw ApiException('Unexpected response for parallel generation stream');
      }

      return consumeParallelGenerationSseStream(
        body,
        slotCount: count,
        onProgress: onProgress,
        onSseEvent: onSseEvent,
      );
    } on DioException catch (e) {
      _throwMappedApiException(e);
    }
  }

  Future<XFile> downloadImageToTemp(
    String imageUrl, {
    void Function(String message)? onProgress,
  }) =>
      ApiServiceLegacyMedia.downloadImageToTemp(
        dio: _dio,
        uuid: _uuid,
        imageUrl: imageUrl,
        onProgress: onProgress,
      );

  /// POST `/api/preprocess-image` — server person detection + consensus.
  ///
  /// Fire-and-forget person-detection call; never throws — returns success=false on any error.
  Future<PreprocessImageResult> preprocessImage({
    required String sessionId,
    int? clientFaceCount,
  }) async {
    final body = <String, dynamic>{
      'sessionId': sessionId,
      if (clientFaceCount != null && clientFaceCount > 0)
        'clientFaceCount': clientFaceCount,
    };

    try {
      final raw = await _apiClient.preprocessImage(body);
      if (raw is Map<String, dynamic>) {
        return PreprocessImageResult.fromJson(raw);
      }
      if (raw is Map) {
        return PreprocessImageResult.fromJson(Map<String, dynamic>.from(raw));
      }
      return const PreprocessImageResult(success: false);
    } on DioException catch (e) {
      _handleWebNetworkError(e);
      AppLogger.debug('preprocessImage failed: ${e.message}');
      return const PreprocessImageResult(success: false);
    } catch (e) {
      AppLogger.debug('preprocessImage failed: $e');
      return const PreprocessImageResult(success: false);
    }
  }
}
