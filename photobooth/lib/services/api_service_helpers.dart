import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;

import '../screens/theme_selection/theme_model.dart';
import '../utils/app_strings.dart';
import '../utils/constants.dart';
import '../utils/exceptions.dart';
import '../utils/logger.dart';
import 'api_session_patch_json.dart';
import 'kiosk_manager.dart';
import 'session_manager.dart';

/// Themes fetch helpers (Sonar S3776 extractions from [ApiService.getThemes]).
Future<Map<String, dynamic>> kioskThemesQueryParameters() async {
  final kioskCode = (await KioskManager().getKioskCode())?.trim().toUpperCase();
  final kioskId = SessionManager().currentSession?.kioskId;
  final qp = <String, dynamic>{};
  if (kioskCode != null && kioskCode.isNotEmpty) {
    qp['kioskCode'] = kioskCode;
  }
  if (kioskId != null && kioskId.isNotEmpty) {
    qp['kioskId'] = kioskId;
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
void logGenerateImageResponseMetadata(Map<String, dynamic> response) {
  final runId = response['runId'] as String?;
  final framing = response['framing'] as Map<String, dynamic>?;
  final timing = response['timing'] as Map<String, dynamic>?;
  final faceVerification = response['faceVerification'] as Map<String, dynamic>?;
  final evaluation = response['evaluation'] as Map<String, dynamic>?;
  if (runId == null && framing == null && timing == null) return;

  AppLogger.debug('📊 Generation metadata:');
  if (runId != null) AppLogger.debug('   Run ID: $runId');
  if (framing != null) {
    AppLogger.debug(
      '   Framing: ${framing['personCount']} person(s), '
      '${framing['orientation']}, ${framing['zoomLevel']}, ${framing['aspectRatio']}',
    );
  }
  if (timing != null) {
    final totalMs = timing['totalMs'] as int?;
    final generationMs = timing['generationMs'] as int?;
    final upscaleMs = timing['upscaleMs'] as int?;
    if (totalMs != null) {
      AppLogger.debug('   Total duration: ${totalMs}ms');
      if (generationMs != null) AppLogger.debug('   Generation: ${generationMs}ms');
      if (upscaleMs != null && upscaleMs > 0) {
        AppLogger.debug('   Upscale: ${upscaleMs}ms');
      }
    }
  }
  if (faceVerification != null) {
    AppLogger.debug(
      '   Face verification: ${faceVerification['originalCount']} original, '
      '${faceVerification['generatedCount']} generated, '
      'match: ${faceVerification['match']}',
    );
  }
  if (evaluation != null) {
    AppLogger.debug(
      '   Evaluation: composite=${evaluation['compositeScore']}, '
      'identity=${evaluation['identityScore']}, prompt=${evaluation['promptScore']}',
    );
  }
}
