import 'package:flutter/material.dart';

import '../screens/theme_selection/theme_model.dart';
import 'app_strings.dart';
import 'classic_shot_mode.dart';
import 'constants.dart';
import 'print_orientation.dart';
import 'route_args.dart';

/// Navigates into Classic / FotoFlashback POSE (skips AI themes + Gemini).
Future<void> navigateToFotoFlashbackCapture({
  required BuildContext context,
  required ThemeModel theme,
  bool replace = false,
  ClassicShotMode shotMode = ClassicShotMode.fourShot,
  PrintOrientation singlePrintOrientation = PrintOrientation.landscape,
}) async {
  if (!context.mounted) return;
  final total = shotMode.shotCount;
  final orientation = shotMode.isSingle6x4
      ? singlePrintOrientation
      : PrintOrientation.landscape;
  final args = CaptureRouteArgs(
    returnPhotoOnly: true,
    multiShotTotal: total,
    flashbackTheme: theme,
    singlePrintOrientation: orientation,
    subtitleHint: shotMode.isSingle6x4
        ? AppStrings.flashbackSinglePrintTitle(
            orientation == PrintOrientation.portrait,
          )
        : AppStrings.flashbackShotProgress(1, total),
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
