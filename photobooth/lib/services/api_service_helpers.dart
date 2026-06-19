import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:uuid/uuid.dart';

import '../screens/result/transformed_image_model.dart';
import '../screens/theme_selection/theme_model.dart';
import 'api_client.dart';
import 'api_image_url_utils.dart';
import '../utils/app_strings.dart';
import '../utils/constants.dart';
import '../utils/exceptions.dart';
import 'api_generate_metadata_log.dart';
import 'api_session_patch_json.dart';
import 'kiosk_manager.dart';

/// Themes fetch helpers (Sonar S3776 extractions from [ApiService.getThemes]).
Future<Map<String, dynamic>> kioskThemesQueryParameters() async {
  final kioskCode = (await KioskManager().getKioskCode())?.trim().toUpperCase();
  final qp = <String, dynamic>{'active': true};
  if (kioskCode != null && kioskCode.isNotEmpty) {
    qp['kiosk'] = kioskCode;
  }
  return qp;
}

List<ThemeModel> parseThemesResponseBody(dynamic data) {
  if (data is! List) {
    throw ApiException('Unexpected themes response from API');
  }
  return data
      .whereType<Map>()
      .map((e) => ThemeModel.fromJson(Map<String, dynamic>.from(e)))
      .toList();
}

bool isWebCorsThemesFetchError(
  DioException e, {
  bool platformIsWeb = kIsWeb,
}) {
  if (!platformIsWeb) return false;
  if (e.type != DioExceptionType.connectionError &&
      e.type != DioExceptionType.unknown) {
    return false;
  }
  final errorMsg = e.message ?? '';
  return errorMsg.contains('XMLHttpRequest') ||
      errorMsg.contains('CORS') ||
      errorMsg.contains(AppStrings.failedToFetch) ||
      errorMsg.contains('NetworkError');
}

Never throwWebCorsThemesFetchError(DioException e) {
  throw ApiException(
    'CORS Error: The API server at ${AppConstants.kBaseUrl} is not configured to allow requests from this origin. '
    'Please contact the server administrator to add CORS headers allowing requests from your domain. '
    'Error details: ${e.message ?? AppStrings.unknownNetworkError}',
  );
}

bool isThemesFetchConnectionError(DioException e) {
  return e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.connectionError;
}

Never rethrowThemesFetchDioError(
  DioException e, {
  bool platformIsWeb = kIsWeb,
}) {
  if (isWebCorsThemesFetchError(e, platformIsWeb: platformIsWeb)) {
    throwWebCorsThemesFetchError(e);
  }
  if (isThemesFetchConnectionError(e)) {
    throw ApiException(
      'Connection error occurred: ${e.message ?? AppConstants.kErrorNetwork}',
    );
  }
  throw ApiException(
    'Failed to fetch themes: ${e.message}',
    e.response?.statusCode,
  );
}

/// PATCH session body assembly.
Map<String, dynamic> buildSessionPatchBody({
  String? userImageUrl,
  String? selectedThemeId,
  bool includeSelectedFrameId = false,
  String? selectedFrameId,
  int? personCount,
  Map<String, dynamic>? framingMetadata,
}) {
  final body = <String, dynamic>{};
  if (userImageUrl != null) body['userImageUrl'] = userImageUrl;
  if (selectedThemeId != null) body['selectedThemeId'] = selectedThemeId;
  if (includeSelectedFrameId) body['selectedFrameId'] = selectedFrameId;
  if (personCount != null) body['personCount'] = personCount;
  if (framingMetadata != null && framingMetadata.isNotEmpty) {
    body['framingMetadata'] = framingMetadata;
  }
  if (body.isEmpty) {
    throw ApiException(
      'At least one of userImageUrl, selectedThemeId, or selectedFrameId '
      '(with includeSelectedFrameId) must be provided',
    );
  }
  return body;
}

Future<Map<String, dynamic>> decodeSessionPatchResponseText(
  String text, {
  bool decodeOnMainIsolate = kIsWeb,
}) async {
  if (text.isEmpty) throw ApiException('Empty session response');
  if (decodeOnMainIsolate) return parseSessionPatchResponseJson(text);
  return compute(parseSessionPatchResponseJson, text);
}

/// Debug logging for POST /api/generate-image metadata block.
/// Single POST /api/generate-image attempt (Sonar S3776 extraction).
Future<TransformedImageModel> generateTransformedImageOnce({
  required ApiClient apiClient,
  required String sessionId,
  required int attempt,
  required String originalPhotoId,
  required String themeId,
  required Uuid uuid,
  void Function(String message)? onProgress,
}) async {
  final response = await apiClient.generateImage({
    'sessionId': sessionId,
    'attempt': attempt,
    'trackDetails': true,
  });
  onProgress?.call('Response received');

  if (response['success'] != true) {
    final errorMsg = response['error'] as String? ?? 'Generation failed';
    throw ApiException(errorMsg);
  }

  final imageUrl = response['imageUrl'] as String?;
  if (imageUrl == null || imageUrl.isEmpty) {
    throw ApiException('No image URL in response');
  }

  logGenerateImageResponseMetadata(response);
  final runId = response['runId'] as String?;
  final resolvedImageUrl = resolveApiImageUrl(imageUrl);

  return TransformedImageModel(
    id: uuid.v4(),
    imageUrl: resolvedImageUrl,
    originalPhotoId: originalPhotoId,
    themeId: themeId,
    transformedAt: DateTime.now(),
    runId: runId,
  );
}

bool isGenerateImageDioTimeout(DioException e) {
  return e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout;
}
