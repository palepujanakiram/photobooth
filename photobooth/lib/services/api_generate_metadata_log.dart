import '../utils/logger.dart';

/// Debug logging for POST /api/generate-image metadata block.
void logGenerateImageResponseMetadata(Map<String, dynamic> response) {
  final runId = response['runId'] as String?;
  final framing = response['framing'] as Map<String, dynamic>?;
  final timing = response['timing'] as Map<String, dynamic>?;
  final faceVerification = response['faceVerification'] as Map<String, dynamic>?;
  final evaluation = response['evaluation'] as Map<String, dynamic>?;
  if (runId == null && framing == null && timing == null) return;

  AppLogger.debug('📊 Generation metadata:');
  _logRunId(runId);
  _logFraming(framing);
  _logTiming(timing);
  _logFaceVerification(faceVerification);
  _logEvaluation(evaluation);
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
