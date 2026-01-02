import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:uuid/uuid.dart';
import '../screens/result/transformed_image_model.dart';
import '../screens/theme_selection/theme_model.dart';
import '../utils/exceptions.dart';
import '../utils/constants.dart';
import 'api_client.dart';
import 'file_helper.dart';

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
                error: 'CORS/Network Error: The API server may not be configured to allow requests from this origin.',
                message: 'CORS/Network Error: ${dioError.message ?? "Unknown network error"}',
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
    if (kIsWeb && (e.type == DioExceptionType.connectionError || 
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
      dynamic tempFile; // Use dynamic to avoid type conflicts between dart:io and dart:html
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
            'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh0cm5lZm9lcXZlYXRqeGZpaWljIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI5NjMwNDYsImV4cCI6MjA3ODUzOTA0Nn0.Fu-PIP3VIKxAQde9dvLqvZqPFdlOCDiHwKL4M1A4nSo',
          },
        ));
        
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

        // Save transformed image - use XFile for cross-platform support
        XFile transformedImageFile;
        final base64String = base64Encode(responseBytes);
        final dataUrl = 'data:image/jpeg;base64,$base64String';
        transformedImageFile = XFile(dataUrl, mimeType: 'image/jpeg', name: 'transformed_${_uuid.v4()}.jpg');

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
        tempFile = FileHelper.createFile('$tempDirPath/upload_${_uuid.v4()}.jpg');
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
      if (kIsWeb && (e.type == DioExceptionType.connectionError || 
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

  /// Updates session with user photo and selected theme
  /// Returns updated session data
  Future<Map<String, dynamic>> updateSession({
    required String sessionId,
    required String userImageUrl, // Base64 data URL
    required String selectedThemeId,
  }) async {
    try {
      final response = await _apiClient.updateSession(
        sessionId,
        {
          'userImageUrl': userImageUrl,
          'selectedThemeId': selectedThemeId,
        },
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
  /// This call can take 10-30 seconds, with a 60-second timeout
  /// Retries once on timeout before showing error
  /// Returns TransformedImageModel with the generated image
  Future<TransformedImageModel> generateImage({
    required String sessionId,
    required int attempt,
    required String originalPhotoId,
    required String themeId,
  }) async {
    // Create a Dio instance with 60-second timeout for this specific call
    final dioWithTimeout = Dio(
      BaseOptions(
        baseUrl: AppConstants.kBaseUrl,
        connectTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
        headers: {
          'Content-Type': 'application/json',
          'Authorization':
              'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh0cm5lZm9lcXZlYXRqeGZpaWljIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI5NjMwNDYsImV4cCI6MjA3ODUzOTA0Nn0.Fu-PIP3VIKxAQde9dvLqvZqPFdlOCDiHwKL4M1A4nSo',
        },
      ),
    );
    
    // Configure browser adapter for web (important for all Dio instances)
    configureDioForWeb(dioWithTimeout);
    
    final apiClientWithTimeout = ApiClient(dioWithTimeout);

    // Retry logic: try once, retry once on timeout
    int retryCount = 0;
    const maxRetries = 1;

    while (retryCount <= maxRetries) {
      try {
        final response = await apiClientWithTimeout.generateImage({
          'sessionId': sessionId,
          'attempt': attempt,
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

        // Parse base64 data URL: data:image/png;base64,iVBORw0KGgo...
        if (!imageUrl.startsWith('data:image/')) {
          throw ApiException('Invalid image format in response');
        }

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

        // Save transformed image - use XFile for cross-platform support
        XFile transformedImageFile;
        if (kIsWeb) {
          // On web, create XFile from data URL directly
          transformedImageFile = XFile(imageUrl, mimeType: mimeType, name: 'transformed_${_uuid.v4()}.$extension');
        } else {
          // On mobile, save to temp file and create XFile
          final tempDirPath = await FileHelper.getTempDirectoryPath();
          final filePath = '$tempDirPath/transformed_${_uuid.v4()}.$extension';
          final file = FileHelper.createFile(filePath);
          await (file as dynamic).writeAsBytes(imageBytes);
          transformedImageFile = XFile((file as dynamic).path);
          
          // Verify the file was written correctly
          if (!(file as dynamic).existsSync()) {
            throw ApiException('Failed to save transformed image file');
          }

          final fileSize = await (file as dynamic).length();
          if (fileSize == 0) {
            throw ApiException('Saved image file is empty');
          }
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

        // Handle error response
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
            errorMessage = isTimeout
                ? 'Request timed out. Please try again.'
                : 'API Error: ${e.response?.statusCode} - ${e.message}';
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
}
