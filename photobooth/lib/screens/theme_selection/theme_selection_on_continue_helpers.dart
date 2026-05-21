import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../../views/widgets/app_snackbar.dart';
import '../photo_capture/photo_model.dart';
import 'theme_model.dart';
import 'theme_selection_continue_helpers.dart';
import 'theme_selection_viewmodel.dart';

/// Continue with an existing capture: session update then navigation (Sonar S3776).
Future<void> themeSelectionContinueWithPhoto({
  required BuildContext context,
  required ThemeViewModel viewModel,
  required PhotoModel photo,
  required ThemeModel selectedTheme,
  required void Function(bool generating) setGenerating,
}) async {
  final currentContext = context;
  setGenerating(true);
  try {
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
