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

/// Encode + optional Gemini scrub for one Classic shot (fail-open → original).
///
/// Kick off as soon as a shot is accepted so Gemini latency hides under the
/// next pose / countdown.
Future<String> scrubClassicShotDataUrl({
  required Future<String> Function() encodeShotDataUrl,
  required bool enableScrub,
  ApiService? apiService,
  SessionManager? sessionManager,
}) async {
  final raw = await encodeShotDataUrl();
  if (!enableScrub) return raw;

  try {
    final sessionId =
        (sessionManager ?? SessionManager()).sessionId?.trim() ?? '';
    if (sessionId.isEmpty) return raw;

    final cleaned = await (apiService ?? ApiService()).cleanStripOverlays(
      sessionId: sessionId,
      images: [raw],
    );
    if (cleaned.length == 1 && cleaned.first.trim().isNotEmpty) {
      AppLogger.debug('Classic per-shot scrub done for session $sessionId');
      return cleaned.first;
    }
  } catch (e, st) {
    AppLogger.warning(
      'Classic per-shot scrub failed (fail-open)',
      error: e,
      stackTrace: st,
    );
  }
  return raw;
}
