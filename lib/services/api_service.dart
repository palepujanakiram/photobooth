import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../screens/result/transformed_image_model.dart';
import '../screens/theme_selection/theme_model.dart';
import '../utils/exceptions.dart';
import '../utils/constants.dart';
import 'api_client.dart';

class ApiService {
  final ApiClient _apiClient;
  final Uuid _uuid = const Uuid();

  ApiService()
      : _apiClient = ApiClient(
          Dio(
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
          ),
        );

  /// Transforms an image using AI with the selected theme.
  ///
  /// Returns the transformed image as a [TransformedImageModel].
  /// Throws [ApiException] if the transformation fails.
  Future<TransformedImageModel> transformImage({
    required File image,
    required ThemeModel theme,
    required String originalPhotoId,
  }) async {
    try {
      final imageBytes = await _apiClient.transformImage(
        theme.promptText,
        theme.negativePrompt ?? '',
        image,
      );

      // Validate that we received image data
      if (imageBytes.isEmpty) {
        throw ApiException('Received empty image data from API');
      }

      // Save transformed image to temporary file
      final tempDir = Directory.systemTemp;
      final transformedImageFile = File(
        '${tempDir.path}/transformed_${_uuid.v4()}.jpg',
      );
      await transformedImageFile.writeAsBytes(imageBytes);

      // Verify the file was written correctly
      if (!transformedImageFile.existsSync()) {
        throw ApiException('Failed to save transformed image file');
      }

      final fileSize = await transformedImageFile.length();
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
      // Filter themes where isActive is true
      return themes.where((theme) => theme.isActive == true).toList();
    } on DioException catch (e) {
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

        // Save transformed image to temporary file
        final tempDir = Directory.systemTemp;
        final transformedImageFile = File(
          '${tempDir.path}/transformed_${_uuid.v4()}.$extension',
        );
        await transformedImageFile.writeAsBytes(imageBytes);

        // Verify the file was written correctly
        if (!transformedImageFile.existsSync()) {
          throw ApiException('Failed to save transformed image file');
        }

        final fileSize = await transformedImageFile.length();
        if (fileSize == 0) {
          throw ApiException('Saved image file is empty');
        }

        return TransformedImageModel(
          id: _uuid.v4(),
          imageFile: transformedImageFile,
          originalPhotoId: originalPhotoId,
          themeId: themeId,
          transformedAt: DateTime.now(),
        );
      } on DioException catch (e) {
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
