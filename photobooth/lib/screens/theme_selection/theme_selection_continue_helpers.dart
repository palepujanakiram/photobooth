import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../../utils/route_args.dart';
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
  required bool mounted,
}) async {
  try {
    await _themeSelectionNavigateAfterFramesLoaded(
      context: context,
      viewModel: viewModel,
      photo: photo,
      selectedTheme: selectedTheme,
      mounted: mounted,
    );
  } catch (_) {
    await _themeSelectionNavigateFrameSelectFallback(
      context: context,
      photo: photo,
      selectedTheme: selectedTheme,
      mounted: mounted,
    );
  }
}

Future<void> _themeSelectionNavigateFrameSelectFallback({
  required BuildContext context,
  required PhotoModel photo,
  required ThemeModel selectedTheme,
  required bool mounted,
}) async {
  if (!mounted || !context.mounted) return;
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
  required bool mounted,
}) async {
  final frames = await viewModel.fetchKioskFramesList();
  if (!mounted || !context.mounted) return;
  if (frames.length >= 2) {
    await _themeSelectionNavigateFrameSelectFallback(
      context: context,
      photo: photo,
      selectedTheme: selectedTheme,
      mounted: mounted,
    );
    return;
  }
  if (frames.length == 1) {
    final ok = await _themeSelectionSyncSingleFrame(
      context: context,
      viewModel: viewModel,
      frameId: frames.single.id,
      mounted: mounted,
    );
    if (!ok) return;
  } else {
    final ok = await _themeSelectionSyncAutoSkippedFrame(
      context: context,
      viewModel: viewModel,
      mounted: mounted,
    );
    if (!ok) return;
  }
  if (!mounted || !context.mounted) return;
  await Navigator.pushNamed(
    context,
    AppConstants.kRouteGenerateProgress,
    arguments: GenerateArgs(photo: photo, theme: selectedTheme),
  );
}

Future<bool> _themeSelectionSyncSingleFrame({
  required BuildContext context,
  required ThemeViewModel viewModel,
  required String frameId,
  required bool mounted,
}) async {
  final frameOk = await viewModel.syncSingleFrameSelection(frameId);
  if (!mounted || !context.mounted) return false;
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
  required bool mounted,
}) async {
  final frameOk = await viewModel.syncAutoSkippedFrameSelection();
  if (!mounted || !context.mounted) return false;
  if (frameOk) return true;
  AppSnackBar.showError(
    context,
    viewModel.errorMessage ?? 'Could not prepare generation.',
  );
  return false;
}
