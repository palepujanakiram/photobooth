import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/app_settings_manager.dart';
import '../../services/session_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../utils/session_photo_sync_helpers.dart';
import '../../views/widgets/app_snackbar.dart';
import '../photo_capture/photo_model.dart';
import 'theme_model.dart';
import 'theme_selection_continue_helpers.dart';
import 'theme_selection_viewmodel.dart';

Future<int> refreshThemeSelectionTriesRemaining(
  AppSettingsManager appSettings,
) async {
  final sm = SessionManager();
  final api = ApiService();
  final sid = sm.sessionId;
  if (sid != null) {
    try {
      final raw = await api.fetchSession(sid);
      if (raw != null) sm.setSessionFromResponse(raw);
    } catch (_) {}
  }
  try {
    await appSettings.fetchSettings();
  } catch (_) {}
  final max = appSettings.settings?.maxRegenerations;
  final maxAllowed = (max != null && max > 0)
      ? max
      : AppConstants.kDefaultMaxRegenerations;
  final used = sm.currentSession?.attemptsUsed ?? 0;
  return (maxAllowed - used).clamp(0, maxAllowed);
}

/// Continue with an existing capture: session update then navigation (Sonar S3776).
Future<void> themeSelectionContinueWithPhoto({
  required BuildContext context,
  required ThemeViewModel viewModel,
  required PhotoModel photo,
  required ThemeModel selectedTheme,
  required void Function(bool generating) setGenerating,
}) async {
  final currentContext = context;
  final appSettings = currentContext.read<AppSettingsManager>();
  setGenerating(true);
  try {
    final tries = await refreshThemeSelectionTriesRemaining(appSettings);
    if (!currentContext.mounted) return;
    if (tries <= 0) {
      AppSnackBar.showError(
        currentContext,
        AppStrings.generationNoAttemptsRemaining,
      );
      return;
    }

    final sessionId = SessionManager().sessionId;
    if (sessionId == null || sessionId.isEmpty) {
      AppSnackBar.showError(
        currentContext,
        AppStrings.sessionPhotoSyncNoSession,
      );
      return;
    }

    final photoSync = await ensureSessionPhotoOnServer(
      sessionId: sessionId,
      photo: photo,
    );
    if (!currentContext.mounted) return;
    if (!photoSync.isReady) {
      AppSnackBar.showError(
        currentContext,
        photoSync.errorMessage ?? AppStrings.sessionPhotoSyncFailed,
      );
      return;
    }

    final success = await viewModel.updateSessionWithTheme();
    if (!currentContext.mounted) return;
    if (success) {
      await themeSelectionNavigateAfterSessionUpdate(
        context: currentContext,
        viewModel: viewModel,
        photo: photo,
        selectedTheme: selectedTheme,
      );
    } else {
      AppSnackBar.showError(
        currentContext,
        viewModel.errorMessage ?? 'Failed to update session with theme',
      );
    }
  } catch (e) {
    if (currentContext.mounted) {
      AppSnackBar.showError(
        currentContext,
        'An error occurred: ${e.toString()}',
      );
    }
  } finally {
    setGenerating(false);
  }
}

/// Continue without capture: open camera and store result (Sonar S3776).
Future<void> themeSelectionContinueToCapture({
  required BuildContext context,
  required void Function(PhotoModel photo) setPhotoFromCapture,
}) async {
  final currentContext = context;
  final result = await Navigator.pushNamed(
    currentContext,
    AppConstants.kRouteCapture,
  );
  if (!currentContext.mounted) return;
  if (result == null || result is! PhotoModel) return;
  setPhotoFromCapture(result);
}
