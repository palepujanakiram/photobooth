import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:uuid/uuid.dart';
import '../screens/result/transformed_image_model.dart';
import '../screens/theme_selection/theme_model.dart';
import '../utils/exceptions.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';
import 'api_client.dart';
import 'file_helper.dart';
import 'api_logging_interceptor.dart';
import 'bugsnag_dio_interceptor.dart';
import '../utils/alice_inspector.dart';
import 'package:alice_dio/alice_dio_adapter.dart';

// Conditional import for web Dio configuration
import 'dio_web_config_stub.dart' if (dart.library.html) 'dio_web_config.dart';

class ApiService {
  late final ApiClient _apiClient;
  final Uuid _uuid = const Uuid();

  ApiService() {
    final dio = Dio(
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
    configureDioForWeb(dio);

    // Add Alice interceptor for in-app network inspection
    // This must be added FIRST to capture all requests
    if (!kIsWeb) {
      // Alice doesn't work well on web, only add for mobile
      final aliceDioAdapter = AliceDioAdapter();
      AliceInspector.instance.addAdapter(aliceDioAdapter);
      dio.interceptors.add(aliceDioAdapter);
    }

    // Add Bugsnag breadcrumbs interceptor to automatically capture network requests
    dio.interceptors.add(BugsnagDioInterceptor());

    // Add logging interceptor to log all API calls
    dio.interceptors.add(ApiLoggingInterceptor());

    // Add error interceptor for web compatibility
    dio.interceptors.add(InterceptorsWrapper(
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

    _apiClient = ApiClient(dio);
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
        dio.interceptors.add(BugsnagDioInterceptor());
        dio.interceptors.add(ApiLoggingInterceptor());

        // Configure browser adapter for web (critical for web platform)
        configureDioForWeb(dio);
        
        // Add logging interceptor
        dio.interceptors.add(ApiLoggingInterceptor());

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

        // Save transformed image - use XFile for cross-platform support
        XFile transformedImageFile;
        final base64String = base64Encode(responseBytes);
        final dataUrl = 'data:image/jpeg;base64,$base64String';
        transformedImageFile = XFile(dataUrl, mimeType: 'image/jpeg');

        return TransformedImageModel(
          id: _uuid.v4(),
          imageFile: transformedImageFile,
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

        // Save transformed image - use XFile for cross-platform support
        final tempDirPath2 = await FileHelper.getTempDirectoryPath();
        final filePath = '$tempDirPath2/transformed_${_uuid.v4()}.jpg';
        final file = FileHelper.createFile(filePath);
        await (file as dynamic).writeAsBytes(responseBytes);
        final transformedImageFile = XFile((file as dynamic).path);

        // Verify the file was written correctly
        if (!(file as dynamic).existsSync()) {
          throw ApiException('Failed to save transformed image file');
        }

        final fileSize = await (file as dynamic).length();
        if (fileSize == 0) {
          throw ApiException('Saved image file is empty');
        }

        return TransformedImageModel(
          id: _uuid.v4(),
          imageFile: transformedImageFile,
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
      final themes = await _apiClient.getThemes();
      return themes.toList();
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

  /// Generates transformed image using AI
  /// This call can take 10-60+ seconds, with a 180-second (3 minute) timeout
  /// Retries once on timeout before showing error
  /// Returns TransformedImageModel with the generated image
  Future<TransformedImageModel> generateImage({
    required String sessionId,
    required int attempt,
    required String originalPhotoId,
    required String themeId,
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
    
    // Add Bugsnag breadcrumbs interceptor
    dioWithTimeout.interceptors.add(BugsnagDioInterceptor());
    
    // Add logging interceptor
    dioWithTimeout.interceptors.add(ApiLoggingInterceptor());

    final apiClientWithTimeout = ApiClient(dioWithTimeout);

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
        final faceVerification = response['faceVerification'] as Map<String, dynamic>?;
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

        // Handle HTTP URL (new format): https://storage.example.com/generated/image.jpg
        // Or legacy base64 data URL: data:image/png;base64,iVBORw0KGgo...
        XFile transformedImageFile;
        
        if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
          // HTTP URL - download the image
          if (kIsWeb) {
            // On web, XFile can accept URLs directly
            transformedImageFile = XFile(imageUrl);
          } else {
            // On mobile, download the image and save to temp file
            AppLogger.debug('📥 Downloading image from: $imageUrl');
            final imageResponse = await dioWithTimeout.get<List<int>>(
              imageUrl,
              options: Options(responseType: ResponseType.bytes),
            );
            
            final imageBytes = imageResponse.data ?? [];
            if (imageBytes.isEmpty) {
              throw ApiException('Downloaded image is empty');
            }

            // Determine file extension from URL
            final extension = imageUrl.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
            
            final tempDirPath = await FileHelper.getTempDirectoryPath();
            final fileName = 'transformed_${_uuid.v4()}.$extension';
            final filePath = '$tempDirPath/$fileName';
            final file = FileHelper.createFile(filePath);
            await (file as dynamic).writeAsBytes(imageBytes);

            // Verify the file was written correctly
            if (!(file as dynamic).existsSync()) {
              throw ApiException(
                  'Failed to save transformed image file at: $filePath');
            }

            final fileSize = await (file as dynamic).length();
            if (fileSize == 0) {
              throw ApiException('Saved image file is empty at: $filePath');
            }

            final savedPath = (file as dynamic).path;
            AppLogger.debug(
                '✅ Saved transformed image: $savedPath ($fileSize bytes)');
            transformedImageFile = XFile(savedPath);

            // Verify XFile can be read
            try {
              final testBytes = await transformedImageFile.readAsBytes();
              if (testBytes.isEmpty) {
                throw ApiException(
                    'XFile created but cannot read bytes from: $savedPath');
              }
              AppLogger.debug(
                  '✅ Verified XFile is readable (${testBytes.length} bytes)');
            } catch (e) {
              throw ApiException(
                  'XFile created but read failed: $e (path: $savedPath)');
            }
          }
        } else if (imageUrl.startsWith('data:image/')) {
          // Legacy base64 data URL support
          // Extract base64 data
          final base64Data = imageUrl.split(',');
          if (base64Data.length != 2) {
            throw ApiException('Invalid base64 data URL format');
          }

          final base64String = base64Data[1];
          final imageBytes = base64Decode(base64String);

          if (imageBytes.isEmpty) {
            throw ApiException('Decoded image is empty');
          }

          // Determine file extension from MIME type
          final mimeType = imageUrl.split(';')[0].split(':')[1];
          final extension = mimeType == 'image/png' ? 'png' : 'jpg';

          if (kIsWeb) {
            // On web, create XFile from data URL directly
            transformedImageFile = XFile(imageUrl, mimeType: mimeType);
          } else {
            // On mobile, save to temp file and create XFile
            final tempDirPath = await FileHelper.getTempDirectoryPath();
            final fileName = 'transformed_${_uuid.v4()}.$extension';
            final filePath = '$tempDirPath/$fileName';
            final file = FileHelper.createFile(filePath);
            await (file as dynamic).writeAsBytes(imageBytes);

            // Verify the file was written correctly
            if (!(file as dynamic).existsSync()) {
              throw ApiException(
                  'Failed to save transformed image file at: $filePath');
            }

            final fileSize = await (file as dynamic).length();
            if (fileSize == 0) {
              throw ApiException('Saved image file is empty at: $filePath');
            }

            final savedPath = (file as dynamic).path;
            AppLogger.debug(
                '✅ Saved transformed image: $savedPath ($fileSize bytes)');
            transformedImageFile = XFile(savedPath);

            // Verify XFile can be read
            try {
              final testBytes = await transformedImageFile.readAsBytes();
              if (testBytes.isEmpty) {
                throw ApiException(
                    'XFile created but cannot read bytes from: $savedPath');
              }
              AppLogger.debug(
                  '✅ Verified XFile is readable (${testBytes.length} bytes)');
            } catch (e) {
              throw ApiException(
                  'XFile created but read failed: $e (path: $savedPath)');
            }
          }
        } else {
          throw ApiException('Invalid image URL format: must be HTTP URL or base64 data URL');
        }

        return TransformedImageModel(
          id: _uuid.v4(),
          imageFile: transformedImageFile,
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
              AppLogger.debug('❌ Generation failed (Run ID: $runId): $errorMessage');
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
