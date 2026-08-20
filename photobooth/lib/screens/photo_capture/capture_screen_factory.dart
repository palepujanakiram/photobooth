import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings_model.dart';
import '../../services/app_settings_manager.dart';
import '../../utils/camera_source_config.dart';
import '../../utils/capture_session_kind.dart';
import '../../utils/route_args.dart';
import 'capture_screen_router.dart';
import 'photo_capture_view.dart';

/// The POSE screen for the configured camera source.
///
/// **Every** entry into POSE must go through here. The capture screen is reached
/// from four places — the named route, AI entry from Terms, AI entry from the
/// experience chooser, and the Classic page builder — and three of them
/// construct the screen directly with a `pushReplacementKioskFade`, because
/// named `routes:` entries build a const screen and drop typed args on Android
/// TV. Putting the choice in the route table alone therefore missed most of the
/// app: the Classic flows kept opening the CameraX screen even with the DSLR
/// selected, and on a box with no built-in camera that hangs on "Starting
/// camera…".
///
/// Selected by ZenAI `cameraConnectionMode=direct_ptp` or
/// `--dart-define=CAMERA_SOURCE=direct_ptp`; otherwise [PhotoCaptureScreen].
/// When PTP is configured but no Canon is attached, falls back to
/// [PhotoCaptureScreen] via [CaptureScreenRouter].
Widget buildCaptureScreen({
  Key? key,
  required CaptureSessionKind sessionKind,
  CaptureRouteArgs? captureArgs,
  BuildContext? context,
  @visibleForTesting AppSettingsModel? settings,
  @visibleForTesting DirectPtpHardwareProbe? hardwareProbe,
}) {
  final resolvedSettings = settings ?? _settingsFromContext(context);
  if (usesDirectPtpCamera(settings: resolvedSettings)) {
    return CaptureScreenRouter(
      key: key,
      sessionKind: sessionKind,
      captureArgs: captureArgs,
      settings: resolvedSettings,
      hardwareProbe: hardwareProbe,
    );
  }
  return PhotoCaptureScreen(
    key: key,
    sessionKind: sessionKind,
    captureArgs: captureArgs,
  );
}

AppSettingsModel? _settingsFromContext(BuildContext? context) {
  if (context == null) return null;
  try {
    return context.read<AppSettingsManager>().settings;
  } catch (_) {
    return null;
  }
}

/// Derives the POSE flow from route arguments, for the named-route entry.
///
/// Absent arguments mean FotoZen — the single-shot AI flow.
CaptureSessionKind captureSessionKindFor(CaptureRouteArgs? args) {
  if (args == null) return CaptureSessionKind.fotoZen;
  final mode = args.classicShotMode;
  if (mode != null) return CaptureSessionKindX.fromClassicShotMode(mode);
  if (args.isFlashbackFourShot) return CaptureSessionKind.classicFourShot;
  if (args.isFlashbackSingle6x4) return CaptureSessionKind.classicOneShot;
  return CaptureSessionKind.fotoZen;
}
