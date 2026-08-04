import 'package:flutter/material.dart';

import '../screens/photo_capture/photo_capture_view.dart';
import '../screens/theme_selection/theme_model.dart';
import 'app_strings.dart';
import 'capture_session_kind.dart';
import 'classic_capture_intent.dart';
import 'classic_shot_mode.dart';
import 'classic_strip_scrub_coordinator.dart';
import 'constants.dart';
import 'kiosk_page_route.dart';
import 'logger.dart';
import 'route_args.dart';

/// Builds Classic POSE route args (theme + strip progress only).
///
/// Shot count comes from [PhotoCaptureScreen.sessionKind], not re-derived later.
CaptureRouteArgs buildClassicCaptureRouteArgs({
  required ThemeModel theme,
  required ClassicShotMode shotMode,
  bool awaitGuestStart = false,
}) {
  final total = shotMode.shotCount;
  return CaptureRouteArgs(
    returnPhotoOnly: true,
    multiShotTotal: total,
    flashbackTheme: theme,
    subtitleHint: shotMode.isSingle6x4
        ? AppStrings.flashbackSingle6x4Title
        : AppStrings.flashbackShotProgress(1, total),
    classicShotMode: shotMode,
    awaitGuestStart: awaitGuestStart,
  );
}

/// Navigates into Classic POSE with an explicit [CaptureSessionKind].
Future<void> navigateToFotoFlashbackCapture({
  required BuildContext context,
  required ThemeModel theme,
  bool replace = false,
  ClassicShotMode shotMode = ClassicShotMode.fourShot,
  bool awaitGuestStart = false,
}) async {
  if (!context.mounted) return;
  final kind = CaptureSessionKindX.fromClassicShotMode(shotMode);
  final args = buildClassicCaptureRouteArgs(
    theme: theme,
    shotMode: shotMode,
    awaitGuestStart: awaitGuestStart,
  );
  ClassicCaptureIntent.beginClassic(mode: shotMode, theme: theme);
  AppLogger.debug(
    'navigateToFotoFlashbackCapture kind=$kind '
    'total=${args.multiShotTotal} replace=$replace '
    'awaitGuestStart=$awaitGuestStart',
  );
  assert(
    !shotMode.isSingle6x4 || args.multiShotTotal == 1,
    'Classic 1-shot must pass multiShotTotal=1',
  );

  final page = PhotoCaptureScreen(
    key: ValueKey<String>(
      'pose-${kind.name}-${args.multiShotTotal}'
      '${awaitGuestStart ? '-await' : ''}',
    ),
    sessionKind: kind,
    captureArgs: args,
  );
  final settings = RouteSettings(
    name: '${AppConstants.kRouteCapture}-${kind.name}',
    arguments: args,
  );

  if (replace) {
    await pushReplacementKioskFade<void, void>(
      context,
      page,
      settings: settings,
    );
    return;
  }
  await Navigator.of(context).push<void>(
    KioskFadePageRoute<void>(page: page, settings: settings),
  );
}

/// Looks Back → fresh Classic POSE (same shot mode), waiting for guest shutter.
Future<void> navigateBackToClassicCaptureFromLooks({
  required BuildContext context,
  required ThemeModel theme,
  required ClassicShotMode shotMode,
}) async {
  if (!context.mounted) return;
  ClassicStripScrubCoordinator.instance.reset();
  AppLogger.debug(
    'navigateBackToClassicCaptureFromLooks mode=$shotMode theme=${theme.id}',
  );
  await navigateToFotoFlashbackCapture(
    context: context,
    theme: theme,
    shotMode: shotMode,
    replace: true,
    awaitGuestStart: true,
  );
}
