import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:uuid/uuid.dart';
import '../models/app_settings_model.dart';
import '../models/payment_initiate_result.dart';
import '../models/parallel_generation_result.dart';
import '../screens/result/transformed_image_model.dart';
import '../screens/theme_selection/theme_model.dart';
import '../utils/exceptions.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';
import 'api_client.dart';
import 'file_helper.dart';
import 'api_logging_interceptor.dart';
import 'alice_inspector.dart';
import 'kiosk_manager.dart';
import 'session_manager.dart';

// Conditional import for web Dio configuration
import 'dio_web_config_stub.dart' if (dart.library.html) 'dio_web_config.dart';

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
        headers: {
          'Content-Type': 'application/json',
          'Authorization':
              'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh0cm5lZm9lcXZlYXRqeGZpaWljIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI5NjMwNDYsImV4cCI6MjA3ODUzOTA0Nn0.Fu-PIP3VIKxAQde9dvLqvZqPFdlOCDiHwKL4M1A4nSo',
        },
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
                errorMsg.contains('Failed to fetch') ||
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
                    'CORS/Network Error: ${dioError.message ?? "Unknown network error"}',
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

  /// GET `/api/payments/status/{paymentId}` — `{ "status": "PENDING" | "APPROVED" | "FAILED" }`.
  /// Poll when FCM is unavailable; returns that map or null on error / non-JSON.
  Future<Map<String, dynamic>?> fetchPaymentStatus(String paymentId) async {
    if (paymentId.isEmpty) return null;
    try {
      final r = await _dio.get<dynamic>(
        '/api/payments/status/$paymentId',
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
        AppLogger.debug('fetchPaymentStatus: ${e.message}');
      }
    } catch (e) {
      if (kDebugMode) {
        AppLogger.debug('fetchPaymentStatus: $e');
      }
    }
    return null;
  }

  /// Helper method to check and handle CORS/network errors on web
  void _handleWebNetworkError(DioException e) {
    if (kIsWeb &&
        (e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.unknown)) {
      final errorMsg = e.message ?? '';
      if (errorMsg.contains('XMLHttpRequest') ||
          errorMsg.contains('CORS') ||
          errorMsg.contains('Failed to fetch') ||
          errorMsg.contains('NetworkError') ||
          errorMsg.contains('connection errored')) {
        throw ApiException(
          'CORS/Network Error: The API server at ${AppConstants.kBaseUrl} may not be configured to allow requests from this origin (${kIsWeb ? "web browser" : "app"}). '
          'This is typically a CORS (Cross-Origin Resource Sharing) issue. '
          'Please ensure the server allows requests from your domain, or contact the server administrator. '
          'Error: ${e.message ?? "Unknown network error"}',
        );
      }
    }
  }

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
          headers: {
            'Authorization':
                'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh0cm5lZm9lcXZlYXRqeGZpaWljIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI5NjMwNDYsImV4cCI6MjA3ODUzOTA0Nn0.Fu-PIP3VIKxAQde9dvLqvZqPFdlOCDiHwKL4M1A4nSo',
          },
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
        );
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw ApiException(AppConstants.kErrorNetwork);
      }

      // Extract error message from response if available
      String errorMessage = AppConstants.kErrorApiCall;
      if (e.response != null) {
        final responseData = e.response?.data;
        if (responseData is Map<String, dynamic>) {
          errorMessage = responseData['message'] as String? ??
              responseData['error'] as String? ??
              'API Error: ${e.response?.statusCode}';
        } else if (responseData is String) {
          errorMessage = responseData;
        } else {
          errorMessage = 'API Error: ${e.response?.statusCode} - ${e.message}';
        }
      } else {
        errorMessage = '${AppConstants.kErrorApiCall}: ${e.message}';
      }

      throw ApiException(
        errorMessage,
        e.response?.statusCode,
      );
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
      final kioskCode = await KioskManager().getKioskCode();
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
            errorMsg.contains('Failed to fetch') ||
            errorMsg.contains('NetworkError')) {
          throw ApiException(
            'CORS Error: The API server at ${AppConstants.kBaseUrl} is not configured to allow requests from this origin. '
            'Please contact the server administrator to add CORS headers allowing requests from your domain. '
            'Error details: ${e.message ?? "Unknown network error"}',
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

  /// Accepts terms and conditions (legacy)
  Future<void> acceptTerms({required String deviceType}) async {
    try {
      await _apiClient.acceptTerms({
        'device_type': deviceType,
        'accepted': true,
      });
    } on DioException catch (e) {
      _handleWebNetworkError(e);

      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw ApiException(AppConstants.kErrorNetwork);
      }

      String errorMessage = AppConstants.kErrorApiCall;
      if (e.response != null) {
        final responseData = e.response?.data;
        if (responseData is Map<String, dynamic>) {
          errorMessage = responseData['message'] as String? ??
              responseData['error'] as String? ??
              'API Error: ${e.response?.statusCode}';
        } else if (responseData is String) {
          errorMessage = responseData;
        } else {
          errorMessage = 'API Error: ${e.response?.statusCode} - ${e.message}';
        }
      } else {
        errorMessage = '${AppConstants.kErrorApiCall}: ${e.message}';
      }

      throw ApiException(
        errorMessage,
        e.response?.statusCode,
      );
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
      _handleWebNetworkError(e);

      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw ApiException(AppConstants.kErrorNetwork);
      }

      String errorMessage = AppConstants.kErrorApiCall;
      if (e.response != null) {
        final responseData = e.response?.data;
        if (responseData is Map<String, dynamic>) {
          errorMessage = responseData['message'] as String? ??
              responseData['error'] as String? ??
              'API Error: ${e.response?.statusCode}';
        } else if (responseData is String) {
          errorMessage = responseData;
        } else {
          errorMessage = 'API Error: ${e.response?.statusCode} - ${e.message}';
        }
      } else {
        errorMessage = '${AppConstants.kErrorApiCall}: ${e.message}';
      }

      throw ApiException(
        errorMessage,
        e.response?.statusCode,
      );
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
  }) async {
    try {
      final response = await _apiClient.acceptTermsAndCreateSession({
        if (kioskCode != null && kioskCode.isNotEmpty) 'kioskCode': kioskCode,
      });
      return response;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw ApiException(AppConstants.kErrorNetwork);
      }

      String errorMessage = AppConstants.kErrorApiCall;
      if (e.response != null) {
        final responseData = e.response?.data;
        if (responseData is Map<String, dynamic>) {
          errorMessage = responseData['message'] as String? ??
              responseData['error'] as String? ??
              'API Error: ${e.response?.statusCode}';
        } else if (responseData is String) {
          errorMessage = responseData;
        } else {
          errorMessage = 'API Error: ${e.response?.statusCode} - ${e.message}';
        }
      } else {
        errorMessage = '${AppConstants.kErrorApiCall}: ${e.message}';
      }

      throw ApiException(
        errorMessage,
        e.response?.statusCode,
      );
    } catch (e) {
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException('${AppConstants.kErrorUnknown}: $e');
    }
  }

  /// Updates session with user photo and/or selected theme
  /// Returns updated session data
  /// Either userImageUrl or selectedThemeId (or both) must be provided
  Future<Map<String, dynamic>> updateSession({
    required String sessionId,
    String? userImageUrl, // Base64 data URL (optional)
    String? selectedThemeId, // Optional - can be set later
  }) async {
    try {
      final body = <String, dynamic>{};

      if (userImageUrl != null) {
        body['userImageUrl'] = userImageUrl;
      }
      if (selectedThemeId != null) {
        body['selectedThemeId'] = selectedThemeId;
      }

      // Ensure at least one field is provided
      if (body.isEmpty) {
        throw ApiException(
            'Either userImageUrl or selectedThemeId must be provided');
      }

      final response = await _apiClient.updateSession(
        sessionId,
        body,
      );
      return response;
    } on DioException catch (e) {
      _handleWebNetworkError(e);

      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw ApiException(AppConstants.kErrorNetwork);
      }

      String errorMessage = AppConstants.kErrorApiCall;
      if (e.response != null) {
        final responseData = e.response?.data;
        if (responseData is Map<String, dynamic>) {
          errorMessage = responseData['message'] as String? ??
              responseData['error'] as String? ??
              'API Error: ${e.response?.statusCode}';
        } else if (responseData is String) {
          errorMessage = responseData;
        } else {
          errorMessage = 'API Error: ${e.response?.statusCode} - ${e.message}';
        }
      } else {
        errorMessage = '${AppConstants.kErrorApiCall}: ${e.message}';
      }

      throw ApiException(
        errorMessage,
        e.response?.statusCode,
      );
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
      _handleWebNetworkError(e);

      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw ApiException(AppConstants.kErrorNetwork);
      }

      String errorMessage = AppConstants.kErrorApiCall;
      if (e.response != null) {
        final responseData = e.response?.data;
        if (responseData is Map<String, dynamic>) {
          errorMessage = responseData['message'] as String? ??
              responseData['error'] as String? ??
              'API Error: ${e.response?.statusCode}';
        } else if (responseData is String) {
          errorMessage = responseData;
        } else {
          errorMessage = 'API Error: ${e.response?.statusCode} - ${e.message}';
        }
      } else {
        errorMessage = '${AppConstants.kErrorApiCall}: ${e.message}';
      }

      throw ApiException(
        errorMessage,
        e.response?.statusCode,
      );
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
      if (raw is! Map<String, dynamic>) {
        throw ApiException(
          '${AppConstants.kErrorApiCall}: unexpected payment response',
        );
      }
      return PaymentInitiateResult.fromJson(raw);
    } on DioException catch (e) {
      _handleWebNetworkError(e);

      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw ApiException(AppConstants.kErrorNetwork);
      }

      String errorMessage = AppConstants.kErrorApiCall;
      if (e.response != null) {
        final responseData = e.response?.data;
        if (responseData is Map<String, dynamic>) {
          errorMessage = responseData['message'] as String? ??
              responseData['error'] as String? ??
              'API Error: ${e.response?.statusCode}';
        } else if (responseData is String) {
          errorMessage = responseData;
        } else {
          errorMessage = 'API Error: ${e.response?.statusCode} - ${e.message}';
        }
      } else {
        errorMessage = '${AppConstants.kErrorApiCall}: ${e.message}';
      }

      throw ApiException(
        errorMessage,
        e.response?.statusCode,
      );
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
        headers: {
          'Content-Type': 'application/json',
          'Authorization':
              'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh0cm5lZm9lcXZlYXRqeGZpaWljIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI5NjMwNDYsImV4cCI6MjA3ODUzOTA0Nn0.Fu-PIP3VIKxAQde9dvLqvZqPFdlOCDiHwKL4M1A4nSo',
        },
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
        final response = await apiClientWithTimeout.generateImage({
          'sessionId': sessionId,
          'attempt': attempt,
          'trackDetails': true, // Enable detailed tracking
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

        // Validate URL format
        if (!imageUrl.startsWith('http://') &&
            !imageUrl.startsWith('https://')) {
          throw ApiException('Invalid image URL format: must be HTTP URL');
        }

        // Just return the URL - no XFile wrapper, no download
        return TransformedImageModel(
          id: _uuid.v4(),
          imageUrl: imageUrl,
          originalPhotoId: originalPhotoId,
          themeId: themeId,
          transformedAt: DateTime.now(),
        );
      } on DioException catch (e) {
        _handleWebNetworkError(e);

        final isTimeout = e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout;

        // If timeout and we haven't retried yet, retry once
        if (isTimeout && retryCount < maxRetries) {
          retryCount++;
          continue; // Retry the request
        }

        // Handle error response according to new API spec
        String errorMessage = AppConstants.kErrorApiCall;
        String? errorDetails;
        String? runId;

        if (e.response != null) {
          final statusCode = e.response?.statusCode;
          final responseData = e.response?.data;

          if (responseData is Map<String, dynamic>) {
            // New API error format: { "error": "...", "details": "...", "runId": "..." }
            errorMessage = responseData['error'] as String? ??
                responseData['message'] as String? ??
                'API Error: $statusCode';
            errorDetails = responseData['details'] as String?;
            runId = responseData['runId'] as String?;

            // Build error message with details if available
            if (errorDetails != null && errorDetails.isNotEmpty) {
              errorMessage = '$errorMessage: $errorDetails';
            }

            // Include runId in debug logs for tracking
            if (runId != null) {
              AppLogger.debug(
                  '❌ Generation failed (Run ID: $runId): $errorMessage');
            }
          } else if (responseData is String) {
            errorMessage = responseData;
          } else {
            errorMessage = isTimeout
                ? 'Request timed out. Please try again.'
                : 'API Error: $statusCode - ${e.message}';
          }
        } else {
          errorMessage = isTimeout
              ? 'Request timed out. Please try again.'
              : '${AppConstants.kErrorNetwork}: ${e.message}';
        }

        throw ApiException(
          errorMessage,
          e.response?.statusCode,
        );
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
  }) async {
    AppLogger.debug(
        '📡 Parallel SSE generation session=$sessionId photo=$originalPhotoId theme=$themeId count=$count');

    final dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.kBaseUrl,
        connectTimeout: AppConstants.kApiTimeout,
        receiveTimeout: AppConstants.kAiGenerationTimeout,
        headers: {
          'Accept': 'text/event-stream',
          'Authorization':
              'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh0cm5lZm9lcXZlYXRqeGZpaWljIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI5NjMwNDYsImV4cCI6MjA3ODUzOTA0Nn0.Fu-PIP3VIKxAQde9dvLqvZqPFdlOCDiHwKL4M1A4nSo',
        },
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

      var buffer = '';
      try {
        await for (final chunk in utf8.decoder.bind(body.stream)) {
          buffer += chunk;
          while (true) {
            final sep = buffer.indexOf('\n\n');
            if (sep < 0) break;
            var block = buffer.substring(0, sep);
            buffer = buffer.substring(sep + 2);
            if (block.endsWith('\r')) {
              block = block.substring(0, block.length - 1);
            }
            _dispatchParallelSseBlock(
              block,
              slots: slots,
              qualityByIndex: qualityByIndex,
              completer: completer,
              onProgress: onProgress,
            );
            if (completer.isCompleted) {
              return await completer.future;
            }
          }
        }
        if (buffer.trim().isNotEmpty) {
          _dispatchParallelSseBlock(
            buffer,
            slots: slots,
            qualityByIndex: qualityByIndex,
            completer: completer,
            onProgress: onProgress,
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
      _handleWebNetworkError(e);

      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw ApiException(AppConstants.kErrorNetwork);
      }

      String errorMessage = AppConstants.kErrorApiCall;
      if (e.response != null) {
        final responseData = e.response?.data;
        if (responseData is Map<String, dynamic>) {
          errorMessage = responseData['error'] as String? ??
              responseData['message'] as String? ??
              'API Error: ${e.response?.statusCode}';
        } else if (responseData is String) {
          errorMessage = responseData;
        } else {
          errorMessage = 'API Error: ${e.response?.statusCode} - ${e.message}';
        }
      } else {
        errorMessage = '${AppConstants.kErrorApiCall}: ${e.message}';
      }

      throw ApiException(errorMessage, e.response?.statusCode);
    }
  }

  Future<XFile> downloadImageToTemp(
    String imageUrl, {
    void Function(String message)? onProgress,
  }) async {
    if (kIsWeb) {
      return XFile(imageUrl);
    }

    final resolvedUrl = _resolveImageUrl(imageUrl);

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
      AppLogger.debug('❌ Image download failed ($status) for $resolvedUrl: $body');

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

  /// Preprocesses image (validation, compression, person detection)
  /// This is a fire-and-forget call - errors are silently ignored
  /// Should be called immediately after uploading photo to save 2-3 seconds during AI generation
  void preprocessImage({
    required String sessionId,
  }) {
    // Fire-and-forget: don't await, don't handle errors
    // If preprocessing fails, the generate endpoint will handle it automatically
    _apiClient.preprocessImage({
      'sessionId': sessionId,
    }).then((_) {
      // Success - preprocessing completed
      AppLogger.debug('✅ Preprocess image completed');
    }).catchError((error) {
      // Silently ignore errors - this is a background optimization
      AppLogger.debug('⚠️ Preprocess image failed (non-critical): $error');
    });
  }
}

void _dispatchParallelSseBlock(
  String block, {
  required List<String> slots,
  required Map<int, double> qualityByIndex,
  required Completer<ParallelGenerationResult> completer,
  void Function(String message)? onProgress,
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

  switch (eventType) {
    case 'start':
      final total = json['total'];
      onProgress?.call(
        total != null
            ? 'Starting parallel generation ($total options)...'
            : 'Starting parallel generation...',
      );
      break;
    case 'image_complete':
      final idx = json['index'] as int?;
      final url = json['imageUrl'] as String?;
      final q = json['qualityScore'];
      if (idx != null &&
          idx >= 0 &&
          idx < slots.length &&
          url != null &&
          url.isNotEmpty) {
        slots[idx] = url;
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
            slots[i] = u;
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
      if (!completer.isCompleted) {
        completer.complete(
          ParallelGenerationResult(
            imageUrlsBySlot: List<String>.from(slots),
            success: json['success'] == true,
            timingTotalMs: totalMs,
            qualityScoreByIndex: Map<int, double>.from(qualityByIndex),
          ),
        );
      }
      break;
    case 'error':
      final msg = json['error'] as String? ?? 'Generation failed';
      if (!completer.isCompleted) {
        completer.completeError(ApiException(msg));
      }
      break;
    default:
      break;
  }
}
