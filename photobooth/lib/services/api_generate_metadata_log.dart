import '../utils/logger.dart';

Map<String, dynamic>? identityVerificationFromResponse(
  Map<String, dynamic> response,
) {
  final raw =
      response['identityVerification'] ?? response['identity_verification'];
  if (raw is Map) {
    return Map<String, dynamic>.from(raw);
  }
  return null;
}

/// Debug logging for POST /api/generate-image metadata block.
void logGenerateImageResponseMetadata(Map<String, dynamic> response) {
  final runId = response['runId'] as String?;
  final framing = response['framing'] as Map<String, dynamic>?;
  final timing = response['timing'] as Map<String, dynamic>?;
  final faceVerification = response['faceVerification'] as Map<String, dynamic>?;
  final evaluation = response['evaluation'] as Map<String, dynamic>?;
  final identityVerification = identityVerificationFromResponse(response);
  if (runId == null &&
      framing == null &&
      timing == null &&
      faceVerification == null &&
      evaluation == null &&
      identityVerification == null) {
    return;
  }

  AppLogger.debug('📊 Generation metadata:');
  _logRunId(runId);
  _logFraming(framing);
  _logTiming(timing);
  _logFaceVerification(faceVerification);
  _logEvaluation(evaluation);
  _logIdentityVerification(identityVerification);
}

void _logRunId(String? runId) {
  if (runId != null) AppLogger.debug('   Run ID: $runId');
}

void _logFraming(Map<String, dynamic>? framing) {
  if (framing == null) return;
  AppLogger.debug(
    '   Framing: ${framing['personCount']} person(s), '
    '${framing['orientation']}, ${framing['zoomLevel']}, ${framing['aspectRatio']}',
  );
}

void _logTiming(Map<String, dynamic>? timing) {
  if (timing == null) return;
  final totalMs = timing['totalMs'] as int?;
  final generationMs = timing['generationMs'] as int?;
  final upscaleMs = timing['upscaleMs'] as int?;
  if (totalMs == null) return;
  AppLogger.debug('   Total duration: ${totalMs}ms');
  if (generationMs != null) AppLogger.debug('   Generation: ${generationMs}ms');
  if (upscaleMs != null && upscaleMs > 0) {
    AppLogger.debug('   Upscale: ${upscaleMs}ms');
  }
}

void _logFaceVerification(Map<String, dynamic>? faceVerification) {
  if (faceVerification == null) return;
  AppLogger.debug(
    '   Face verification: ${faceVerification['originalCount']} original, '
    '${faceVerification['generatedCount']} generated, '
    'match: ${faceVerification['match']}',
  );
}

void _logEvaluation(Map<String, dynamic>? evaluation) {
  if (evaluation == null) return;
  AppLogger.debug(
    '   Evaluation: composite=${evaluation['compositeScore']}, '
    'identity=${evaluation['identityScore']}, prompt=${evaluation['promptScore']}',
  );
}

void _logIdentityVerification(Map<String, dynamic>? identityVerification) {
  if (identityVerification == null) return;
  final passed = identityVerification['passed'];
  final minScore = identityVerification['minFaceScore'] ??
      identityVerification['embeddingMinSimilarity'];
  final avgScore = identityVerification['avgFaceScore'] ??
      identityVerification['embeddingAvgSimilarity'];
  final threshold = identityVerification['thresholdUsed'] ??
      identityVerification['embeddingThresholdUsed'];
  final retries = identityVerification['retryCount'];
  final failed = identityVerification['failedFaceIndices'] ??
      identityVerification['embeddingFailedFaceIndices'];
  final personCountMatch = identityVerification['personCountMatch'];
  AppLogger.debug(
    '   Identity verification: passed=$passed personCountMatch=$personCountMatch '
    'min=$minScore avg=$avgScore threshold=$threshold '
    'retries=$retries failedFaces=$failed',
  );
}
