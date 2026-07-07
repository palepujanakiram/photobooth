import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_settings_manager.dart';
import '../../utils/constants.dart';
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
  try {
    await _themeSelectionNavigateAfterFramesLoaded(
      context: context,
      viewModel: viewModel,
      photo: photo,
      selectedTheme: selectedTheme,
    );
  } catch (_) {
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
    await _themeSelectionNavigateFrameSelectFallback(
      context: context,
      photo: photo,
      selectedTheme: selectedTheme,
    );
    return;
  }
  if (frames.length == 1) {
    final ok = await _themeSelectionSyncSingleFrame(
      context: context,
      viewModel: viewModel,
      frameId: frames.single.id,
    );
    if (!ok) return;
  } else {
    final ok = await _themeSelectionSyncAutoSkippedFrame(
      context: context,
      viewModel: viewModel,
    );
    if (!ok) return;
  }
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
  );
}

Future<bool> _themeSelectionSyncSingleFrame({
  required BuildContext context,
  required ThemeViewModel viewModel,
  required String frameId,
}) async {
  final frameOk = await viewModel.syncSingleFrameSelection(frameId);
  if (!context.mounted) return false;
  if (frameOk) return true;
  AppSnackBar.showError(
    context,
    viewModel.errorMessage ?? 'Could not prepare generation.',
  );
  return false;
}

Future<bool> _themeSelectionSyncAutoSkippedFrame({
  required BuildContext context,
  required ThemeViewModel viewModel,
}) async {
  final frameOk = await viewModel.syncAutoSkippedFrameSelection();
  if (!context.mounted) return false;
  if (frameOk) return true;
  AppSnackBar.showError(
    context,
    viewModel.errorMessage ?? 'Could not prepare generation.',
  );
  return false;
}
