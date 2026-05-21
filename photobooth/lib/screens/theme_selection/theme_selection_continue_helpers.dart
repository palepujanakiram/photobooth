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
    final frames = await viewModel.fetchKioskFramesList();
    if (!mounted || !context.mounted) return;
    if (frames.length >= 2) {
      await Navigator.pushNamed(
        context,
        AppConstants.kRouteFrameSelect,
        arguments: {
          'photo': photo,
          'theme': selectedTheme,
        },
      );
      return;
    }
    if (frames.length == 1) {
      final frameOk = await viewModel.syncSingleFrameSelection(frames.single.id);
      if (!mounted || !context.mounted) return;
      if (!frameOk) {
        AppSnackBar.showError(
          context,
          viewModel.errorMessage ?? 'Could not prepare generation.',
        );
        return;
      }
    } else {
      final frameOk = await viewModel.syncAutoSkippedFrameSelection();
      if (!mounted || !context.mounted) return;
      if (!frameOk) {
        AppSnackBar.showError(
          context,
          viewModel.errorMessage ?? 'Could not prepare generation.',
        );
        return;
      }
    }
    await Navigator.pushNamed(
      context,
      AppConstants.kRouteGenerateProgress,
      arguments: GenerateArgs(photo: photo, theme: selectedTheme),
    );
  } catch (_) {
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
}
