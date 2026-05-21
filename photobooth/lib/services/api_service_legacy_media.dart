import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:uuid/uuid.dart';

import '../screens/result/transformed_image_model.dart';
import '../screens/theme_selection/theme_model.dart';
import '../utils/app_config.dart';
import '../utils/constants.dart';
import '../utils/exceptions.dart';
import '../utils/logger.dart';
import 'alice_inspector.dart';
import 'api_client.dart';
import 'api_dio_errors.dart';
import 'api_image_url_utils.dart';
import 'api_logging_interceptor.dart';
import 'client_identification.dart';
import 'dio_web_config_stub.dart' if (dart.library.html) 'dio_web_config.dart';
import 'file_helper.dart';

/// Legacy media upload/download helpers (not used by the main kiosk SSE flow).
class ApiServiceLegacyMedia {
  ApiServiceLegacyMedia._();

  static Future<TransformedImageModel> transformImage({
    required ApiClient apiClient,
    required Uuid uuid,
    required XFile image,
    required ThemeModel theme,
    required String originalPhotoId,
  }) async {
    try {
      dynamic tempFile;
      if (kIsWeb) {
        final imageBytes = await image.readAsBytes();
        final multipartFile = MultipartFile.fromBytes(
          imageBytes,
          filename: image.name,
        );

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
        if (responseBytes.isEmpty) {
          throw ApiException('Received empty image data from API');
        }

        final base64String = base64Encode(responseBytes);
        final dataUrl = 'data:image/jpeg;base64,$base64String';

        return TransformedImageModel(
          id: uuid.v4(),
          imageUrl: dataUrl,
          originalPhotoId: originalPhotoId,
          themeId: theme.id,
          transformedAt: DateTime.now(),
          runId: null,
        );
      } else {
        final imageBytes = await image.readAsBytes();
        final tempDirPath = await FileHelper.getTempDirectoryPath();
        tempFile =
            FileHelper.createFile('$tempDirPath/upload_${uuid.v4()}.jpg');
        await (tempFile as dynamic).writeAsBytes(imageBytes);

        final responseBytes = await apiClient.transformImage(
          theme.promptText,
          theme.negativePrompt ?? '',
          tempFile as dynamic,
        );

        if ((tempFile as dynamic).existsSync()) {
          await (tempFile as dynamic).delete();
        }

        if (responseBytes.isEmpty) {
          throw ApiException('Received empty image data from API');
        }

        final tempDirPath2 = await FileHelper.getTempDirectoryPath();
        final filePath = '$tempDirPath2/transformed_${uuid.v4()}.jpg';
        final file = FileHelper.createFile(filePath);
        await (file as dynamic).writeAsBytes(responseBytes);

        if (!(file as dynamic).existsSync()) {
          throw ApiException('Failed to save transformed image file');
        }

        final fileSize = await (file as dynamic).length();
        if (fileSize == 0) {
          throw ApiException('Saved image file is empty');
        }

        final localFileUrl = 'file://${(file as dynamic).path}';

        return TransformedImageModel(
          id: uuid.v4(),
          imageUrl: localFileUrl,
          localFile: XFile((file as dynamic).path),
          originalPhotoId: originalPhotoId,
          themeId: theme.id,
          transformedAt: DateTime.now(),
          runId: null,
        );
      }
    } on DioException catch (e) {
      throwMappedApiException(e);
    } catch (e) {
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException('${AppConstants.kErrorUnknown}: $e');
    }
  }

  static Future<XFile> downloadImageToTemp({
    required Dio dio,
    required Uuid uuid,
    required String imageUrl,
    void Function(String message)? onProgress,
  }) async {
    if (kIsWeb) {
      return XFile(imageUrl);
    }

    final resolvedUrl = withGeneratedImageSessionId(resolveApiImageUrl(imageUrl));

    final previousConnectTimeout = dio.options.connectTimeout;
    final previousReceiveTimeout = dio.options.receiveTimeout;
    dio.options = dio.options.copyWith(
      connectTimeout: AppConstants.kAiGenerationTimeout,
      receiveTimeout: AppConstants.kAiGenerationTimeout,
    );

    AppLogger.debug('📥 Downloading image from: $resolvedUrl');
    final extension = resolvedUrl.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final tempDirPath = await FileHelper.getTempDirectoryPath();
    final fileName = 'transformed_${uuid.v4()}.$extension';
    final filePath = '$tempDirPath/$fileName';
    final file = FileHelper.createFile(filePath);

    onProgress?.call('Downloading result...');
    var lastReportedPercent = -1;
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
      await attemptDownload(headers: dio.options.headers);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      AppLogger.error(
        'Image download failed ($status) for $resolvedUrl: $body',
        error: e,
        stackTrace: e.stackTrace,
      );

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
      dio.options = dio.options.copyWith(
        connectTimeout: previousConnectTimeout,
        receiveTimeout: previousReceiveTimeout,
      );
    }

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
}
