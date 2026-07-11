import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/preprocess_image_result.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../utils/constants.dart';
import '../../utils/theme_filter.dart';

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
  final existing = sessionManager.personCount;
  if (existing != null && existing > 2) return;

  try {
    final runPreprocess =
        preprocessFn ?? ((id) => apiService.preprocessImage(sessionId: id));
    final preprocess = await runPreprocess(sessionId)
        .timeout(AppConstants.kPreprocessTimeout);
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
