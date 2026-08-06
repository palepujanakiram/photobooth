import 'dart:async';

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

/// Serializes Classic Gemini scrub calls so concurrent accepts do not race the
/// image API (parallel cleans often succeed only for the first shot).
class ClassicStripScrubGate {
  ClassicStripScrubGate._();

  static final _instance = ClassicStripScrubGate._();

  static Future<void> _chain = Future<void>.value();

  /// Runs [fn] after prior scrub work; errors do not break the queue.
  static Future<T> enqueue<T>(Future<T> Function() fn) {
    final done = Completer<T>();
    _chain = _chain.then((_) async {
      try {
        done.complete(await fn());
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    // Keep the chain alive after a scrub failure.
    _chain = _chain.catchError((Object _) {});
    return done.future;
  }

  /// Test-only: reset queue between cases.
  static void resetForTests() {
    _chain = Future<void>.value();
    // Keep singleton initialized for coverage of private constructor.
    _instance.hashCode;
  }
}

/// Encode + optional Gemini scrub for one Classic shot (fail-open → original).
///
/// Kick off as soon as a shot is accepted so Gemini latency hides under the
/// next pose / countdown. Scrubs are **serialized** via [ClassicStripScrubGate].
///
/// When [isCancelled] returns true (e.g. Retake last), the gate slot is released
/// without calling Gemini so later shots are not starved.
Future<ClassicShotScrubResult> scrubClassicShotDataUrl({
  required Future<String> Function() encodeShotDataUrl,
  required bool enableScrub,
  ApiService? apiService,
  SessionManager? sessionManager,
  bool Function()? isCancelled,
}) async {
  final raw = await encodeShotDataUrl();
  if (!enableScrub || isCancelled?.call() == true) {
    return ClassicShotScrubResult(dataUrl: raw, scrubbed: false);
  }

  return ClassicStripScrubGate.enqueue(() async {
    if (isCancelled?.call() == true) {
      return ClassicShotScrubResult(dataUrl: raw, scrubbed: false);
    }
    return _scrubEncodedShot(
      raw: raw,
      apiService: apiService,
      sessionManager: sessionManager,
    );
  });
}

Future<ClassicShotScrubResult> _scrubEncodedShot({
  required String raw,
  ApiService? apiService,
  SessionManager? sessionManager,
}) async {
  try {
    final sessionId =
        (sessionManager ?? SessionManager()).sessionId?.trim() ?? '';
    if (sessionId.isEmpty) {
      return ClassicShotScrubResult(dataUrl: raw, scrubbed: false);
    }

    final result = await (apiService ?? ApiService()).cleanStripOverlays(
      sessionId: sessionId,
      images: [raw],
    );
    if (result.images.length == 1 && result.images.first.trim().isNotEmpty) {
      final url = result.images.first;
      final scrubbed =
          !result.skipped &&
          result.cleanedFlags.length == 1 &&
          result.cleanedFlags.first;
      if (scrubbed) {
        AppLogger.debug('Classic per-shot scrub done for session $sessionId');
      } else {
        AppLogger.warning(
          'Classic per-shot scrub did not clean image for $sessionId '
          '(skipped=${result.skipped})',
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
