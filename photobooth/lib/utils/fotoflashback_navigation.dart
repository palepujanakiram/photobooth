import 'package:flutter/material.dart';

import '../models/strip_models.dart';
import '../screens/theme_selection/theme_model.dart';
import 'app_strings.dart';
import 'constants.dart';
import 'route_args.dart';

/// Navigates into FotoFlashback multi-shot POSE (skips frames + Gemini).
Future<void> navigateToFotoFlashbackCapture({
  required BuildContext context,
  required ThemeModel theme,
  bool replace = false,
}) async {
  if (!context.mounted) return;
  final args = CaptureRouteArgs(
    returnPhotoOnly: true,
    multiShotTotal: kStripShotCount,
    flashbackTheme: theme,
    subtitleHint: AppStrings.flashbackShotProgress(1, kStripShotCount),
  );
  if (replace) {
    await Navigator.of(context).pushReplacementNamed(
      AppConstants.kRouteCapture,
      arguments: args,
    );
    return;
  }
  await Navigator.of(context).pushNamed(
    AppConstants.kRouteCapture,
    arguments: args,
  );
}
