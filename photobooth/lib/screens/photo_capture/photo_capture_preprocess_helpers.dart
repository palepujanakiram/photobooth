import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/preprocess_image_result.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../utils/constants.dart';
import '../../utils/kiosk_offline_ux.dart';
import '../../utils/theme_filter.dart';

/// One `/api/preprocess-image` per session: capture and generate share this.
class SessionPreprocessCoordinator {
  SessionPreprocessCoordinator._();

  static final SessionPreprocessCoordinator instance =
      SessionPreprocessCoordinator._();

  String? _sessionId;
  Future<PreprocessImageResult>? _inflight;
  bool _completed = false;

  @visibleForTesting
  void reset() {
    _sessionId = null;
    _inflight = null;
    _completed = false;
  }

  bool isCompletedFor(String sessionId) =>
      _completed && _sessionId == sessionId;

  Future<PreprocessImageResult>? inflightFor(String sessionId) {
    if (_sessionId != sessionId) return null;
    return _inflight;
  }

  Future<PreprocessImageResult> track({
    required String sessionId,
    required Future<PreprocessImageResult> future,
  }) {
    _sessionId = sessionId;
    _completed = false;
    final tracked = future.then((result) {
      _markSettled(sessionId, completed: true);
      return result;
    }, onError: (Object error, StackTrace stack) {
      // Timeout/network: allow generate to retry. Only skip after success.
      _markSettled(sessionId, completed: false);
      return Future<PreprocessImageResult>.error(error, stack);
    });
    _inflight = tracked;
    return tracked;
  }

  void _markSettled(String sessionId, {required bool completed}) {
    if (_sessionId != sessionId) return;
    _completed = completed;
    _inflight = null;
  }
}

/// Joins an in-flight preprocess or starts one (with the capture timeout).
Future<PreprocessImageResult> runOrJoinSessionPreprocess({
  required String sessionId,
  required Future<PreprocessImageResult> Function(String sessionId) preprocessFn,
}) {
  final gate = SessionPreprocessCoordinator.instance;
  final inflight = gate.inflightFor(sessionId);
  if (inflight != null) return inflight;
  return gate.track(
    sessionId: sessionId,
    future: preprocessFn(sessionId).timeout(AppConstants.kPreprocessTimeout),
  );
}

/// Resolves person count after upload preprocess (or when it fails/times out).
int resolvePersonCountAfterPreprocess({
  PreprocessImageResult? preprocess,
  required int clientFaceCount,
  int? sessionPersonCount,
}) {
  final fromPreprocess = preprocess?.personCount;
  if (fromPreprocess != null && fromPreprocess > 0) return fromPreprocess;
  if (sessionPersonCount != null && sessionPersonCount > 0) {
    return sessionPersonCount;
  }
  if (clientFaceCount > 0) return clientFaceCount;
  return ThemeFilter.effectivePersonCount(null);
}

/// Whether preprocess explicitly failed with no usable person count signals.
bool isHardPreprocessFailure({
  required PreprocessImageResult preprocess,
  required int clientFaceCount,
  int? sessionPersonCount,
}) {
  if (preprocess.success) return false;
  if (preprocess.personCount != null && preprocess.personCount! > 0) {
    return false;
  }
  if (clientFaceCount > 0) return false;
  if (sessionPersonCount != null && sessionPersonCount > 0) return false;
  return true;
}

/// Blocks generation until `/api/preprocess-image` has refined person count when needed.
Future<void> ensureAuthoritativePersonCount({
  required SessionManager sessionManager,
  required ApiService apiService,
  required String sessionId,
  @visibleForTesting
  Future<PreprocessImageResult> Function(String sessionId)? preprocessFn,
}) async {
  if (KioskOfflineUx.shouldSkipGeminiPreprocess(
    sessionOffline: sessionManager.isOfflineSession,
  )) {
    return;
  }
  final existing = sessionManager.personCount;
  if (existing != null && existing > 2) return;
  if (SessionPreprocessCoordinator.instance.isCompletedFor(sessionId)) {
    return;
  }

  try {
    final preprocess = await runOrJoinSessionPreprocess(
      sessionId: sessionId,
      preprocessFn:
          preprocessFn ?? ((id) => apiService.preprocessImage(sessionId: id)),
    );
    final refined = resolvePersonCountAfterPreprocess(
      preprocess: preprocess,
      clientFaceCount: 0,
      sessionPersonCount: existing,
    );
    if (refined > 0) {
      sessionManager.setPersonCount(refined);
    }
  } on TimeoutException {
    // Keep best-effort session count; generation can proceed.
  } catch (_) {
    // Preprocess is advisory for orientation; do not block generation.
  }
}
