import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_settings_manager.dart';
import '../../utils/constants.dart';
import '../../utils/classic_shot_mode.dart';
import '../../utils/fotoflashback_navigation.dart';
import '../../services/session_manager.dart';
import '../../utils/payment_workflow_helpers.dart';
import '../../views/widgets/app_snackbar.dart';
import '../photo_capture/photo_model.dart';
import 'theme_model.dart';
import 'theme_selection_viewmodel.dart';

/// Navigation after theme continue (Sonar S3776 extraction).
Future<void> themeSelectionNavigateAfterSessionUpdate({
  required BuildContext context,
  required ThemeViewModel viewModel,
  required PhotoModel photo,
  required ThemeModel selectedTheme,
}) async {
  if (selectedTheme.isPhotoStrip) {
    // Strip themes always use the 4-pose Classic flow (explicit — never rely on
    // a default that could silently turn 1-shot entry points into a loop).
    await navigateToFotoFlashbackCapture(
      context: context,
      theme: selectedTheme,
      shotMode: ClassicShotMode.fourShot,
    );
    return;
  }
  try {
    await _themeSelectionNavigateAfterFramesLoaded(
      context: context,
      viewModel: viewModel,
      photo: photo,
      selectedTheme: selectedTheme,
    );
  } catch (_) {
    if (!context.mounted) return;
    final ok = await _themeSelectionPatchTheme(
      context: context,
      viewModel: viewModel,
    );
    if (!ok) return;
    if (!context.mounted) return;
    await _themeSelectionNavigateFrameSelectFallback(
      context: context,
      photo: photo,
      selectedTheme: selectedTheme,
    );
  }
}

Future<void> _themeSelectionNavigateFrameSelectFallback({
  required BuildContext context,
  required PhotoModel photo,
  required ThemeModel selectedTheme,
}) async {
  if (!context.mounted) return;
  await Navigator.pushNamed(
    context,
    AppConstants.kRouteFrameSelect,
    arguments: {
      'photo': photo,
      'theme': selectedTheme,
    },
  );
}

Future<void> _themeSelectionNavigateAfterFramesLoaded({
  required BuildContext context,
  required ThemeViewModel viewModel,
  required PhotoModel photo,
  required ThemeModel selectedTheme,
}) async {
  final frames = await viewModel.fetchKioskFramesList();
  if (!context.mounted) return;
  if (frames.length >= 2) {
    final ok = await _themeSelectionPatchTheme(
      context: context,
      viewModel: viewModel,
    );
    if (!ok) return;
    if (!context.mounted) return;
    await _themeSelectionNavigateFrameSelectFallback(
      context: context,
      photo: photo,
      selectedTheme: selectedTheme,
    );
    return;
  }
  final ok = await _themeSelectionPatchTheme(
    context: context,
    viewModel: viewModel,
    includeSelectedFrameId: true,
    selectedFrameId: frames.length == 1 ? frames.single.id : null,
  );
  if (!ok) return;
  if (!context.mounted) return;
  await navigateToGenerationOrPrePayment(
    context: context,
    photo: photo,
    theme: selectedTheme,
    replace: false,
    paymentCollectionTiming: context
        .read<AppSettingsManager>()
        .settings
        ?.paymentCollectionTiming,
    wanDown: SessionManager().isOfflineSession,
  );
}

Future<bool> _themeSelectionPatchTheme({
  required BuildContext context,
  required ThemeViewModel viewModel,
  bool includeSelectedFrameId = false,
  String? selectedFrameId,
}) async {
  final ok = await viewModel.updateSessionWithTheme(
    includeSelectedFrameId: includeSelectedFrameId,
    selectedFrameId: selectedFrameId,
  );
  if (!context.mounted) return false;
  if (ok) return true;
  AppSnackBar.showError(
    context,
    viewModel.errorMessage ?? 'Failed to update session with theme',
  );
  return false;
}
