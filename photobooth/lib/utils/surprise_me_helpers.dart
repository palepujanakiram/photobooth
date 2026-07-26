import 'package:flutter/material.dart';

import '../models/strip_models.dart';
import '../screens/fotoflashback/surprise_me_upsell_view.dart';
import '../screens/photo_generate/photo_generate_viewmodel.dart';
import '../screens/theme_selection/theme_model.dart';
import '../services/api_service.dart';
import '../services/session_manager.dart';
import 'app_strings.dart';
import 'constants.dart';
import 'logger.dart';
import 'payment_workflow_helpers.dart';

/// Fail-open: kick off Classic Surprise Me after shot 1 is accepted.
Future<void> maybeKickoffSurpriseMeAfterShot1({
  required Future<String> Function() encodeShotDataUrl,
  required bool enableSurpriseMeAi,
  ApiService? apiService,
  SessionManager? sessionManager,
}) async {
  try {
    if (!enableSurpriseMeAi) return;
    final paymentsEnabled = await resolvePaymentsEnabled();
    if (!paymentsEnabled) return;

    final sessionId = (sessionManager ?? SessionManager()).sessionId;
    if (sessionId == null || sessionId.isEmpty) return;

    final dataUrl = await encodeShotDataUrl();
    await (apiService ?? ApiService()).startSurpriseMe(
      sessionId: sessionId,
      imageDataUrl: dataUrl,
    );
    AppLogger.debug('Surprise Me kickoff accepted for session $sessionId');
  } catch (e, st) {
    AppLogger.warning(
      'Surprise Me kickoff skipped (fail-open)',
      error: e,
      stackTrace: st,
    );
  }
}

/// Single non-blocking status check. Never waits for AI to finish.
Future<SurpriseMeStatus?> fetchSurpriseMeIfReady({
  ApiService? apiService,
  SessionManager? sessionManager,
}) async {
  try {
    final sessionId = (sessionManager ?? SessionManager()).sessionId;
    if (sessionId == null || sessionId.isEmpty) return null;
    return await (apiService ?? ApiService()).fetchSurpriseMeStatus(sessionId);
  } catch (e, st) {
    AppLogger.warning(
      'Surprise Me status skipped (fail-open)',
      error: e,
      stackTrace: st,
    );
    return null;
  }
}

GeneratedImage? surpriseImageFromStatus(SurpriseMeStatus status) {
  if (!status.showUpsell) return null;
  final url = status.imageUrl?.trim() ?? '';
  if (url.isEmpty) return null;
  final themeName = status.themeName?.trim();
  return GeneratedImage(
    id: 'surprise_${DateTime.now().millisecondsSinceEpoch}',
    imageUrl: url,
    theme: ThemeModel(
      id: status.themeId ?? 'surprise_me',
      categoryId: 'surprise',
      name: (themeName != null && themeName.isNotEmpty)
          ? themeName
          : AppStrings.surpriseMeUpsellTitle,
      description: '',
      promptText: '',
    ),
    isSelected: true,
    printSize: AppConstants.kPrintSizePortrait4x6,
  );
}

/// After strip compose: show upsell only if AI is already ready + above threshold.
/// Returns the AI [GeneratedImage] when the guest accepts; otherwise null.
Future<GeneratedImage?> maybeOfferSurpriseMeCopy({
  required BuildContext context,
  required bool enableSurpriseMeAi,
  required int additionalPrintPrice,
  ApiService? apiService,
  SessionManager? sessionManager,
}) async {
  try {
    if (!enableSurpriseMeAi) return null;
    final paymentsEnabled = await resolvePaymentsEnabled();
    if (!paymentsEnabled) return null;
    if (!context.mounted) return null;

    final status = await fetchSurpriseMeIfReady(
      apiService: apiService,
      sessionManager: sessionManager,
    );
    if (status == null || !status.showUpsell) return null;

    final surprise = surpriseImageFromStatus(status);
    if (surprise == null) return null;
    if (!context.mounted) return null;

    final accepted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SurpriseMeUpsellScreen(
          surpriseImage: surprise,
          additionalPrintPrice: additionalPrintPrice,
        ),
      ),
    );

    if (accepted == true) return surprise;

    final sessionId = (sessionManager ?? SessionManager()).sessionId;
    if (sessionId != null && sessionId.isNotEmpty) {
      try {
        await (apiService ?? ApiService()).declineSurpriseMe(sessionId);
      } catch (_) {
        // fail-open
      }
    }
    return null;
  } catch (e, st) {
    AppLogger.warning(
      'Surprise Me upsell skipped (fail-open)',
      error: e,
      stackTrace: st,
    );
    return null;
  }
}
