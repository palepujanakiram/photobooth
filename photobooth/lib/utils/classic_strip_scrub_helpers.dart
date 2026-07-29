import '../services/api_service.dart';
import '../services/session_manager.dart';
import 'constants.dart';
import 'logger.dart';

/// True when Classic AF/OSD scrub should run (admin master switch + kill-switch).
/// Unset admin value defaults to ON (matches server `enableOsdScrub !== false`).
bool classicOverlayScrubEnabled(bool? enableOsdScrub) {
  if (!AppConstants.kEnableStripOverlayCleanup) return false;
  return enableOsdScrub != false;
}

/// Result of per-shot Classic scrub (fail-open keeps [dataUrl] on error).
class ClassicShotScrubResult {
  const ClassicShotScrubResult({
    required this.dataUrl,
    required this.scrubbed,
  });

  final String dataUrl;
  /// True only when the server returned a successful clean (not skipped/failed).
  final bool scrubbed;
}

/// Encode + optional Gemini scrub for one Classic shot (fail-open → original).
///
/// Kick off as soon as a shot is accepted so Gemini latency hides under the
/// next pose / countdown.
Future<ClassicShotScrubResult> scrubClassicShotDataUrl({
  required Future<String> Function() encodeShotDataUrl,
  required bool enableScrub,
  ApiService? apiService,
  SessionManager? sessionManager,
}) async {
  final raw = await encodeShotDataUrl();
  if (!enableScrub) {
    return ClassicShotScrubResult(dataUrl: raw, scrubbed: false);
  }

  try {
    final sessionId =
        (sessionManager ?? SessionManager()).sessionId?.trim() ?? '';
    if (sessionId.isEmpty) {
      return ClassicShotScrubResult(dataUrl: raw, scrubbed: false);
    }

    final cleaned = await (apiService ?? ApiService()).cleanStripOverlays(
      sessionId: sessionId,
      images: [raw],
    );
    if (cleaned.length == 1 && cleaned.first.trim().isNotEmpty) {
      final url = cleaned.first;
      // Identical payload usually means skipped/fail-open echo — not scrubbed.
      final scrubbed = url != raw;
      if (scrubbed) {
        AppLogger.debug('Classic per-shot scrub done for session $sessionId');
      } else {
        AppLogger.warning(
          'Classic per-shot scrub returned unchanged image for $sessionId',
        );
      }
      return ClassicShotScrubResult(dataUrl: url, scrubbed: scrubbed);
    }
  } catch (e, st) {
    AppLogger.warning(
      'Classic per-shot scrub failed (fail-open)',
      error: e,
      stackTrace: st,
    );
  }
  return ClassicShotScrubResult(dataUrl: raw, scrubbed: false);
}
