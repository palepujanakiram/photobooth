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
        theme.prompt,
        theme.negativePrompt,
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
  Future<List<ThemeModel>> getThemes() async {
    try {
      return await _apiClient.getThemes();
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

  /// Accepts terms and conditions
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
}
