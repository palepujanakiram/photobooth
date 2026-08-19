import 'dart:async' show TimeoutException, unawaited;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../services/uvc_session_coordinator.dart';
import '../../services/event_manager.dart';
import '../../utils/constants.dart';
import '../../utils/event_station_role.dart';
import '../../utils/route_args.dart';
import '../../utils/web_flow_trace.dart';
import '../../utils/logger.dart';
import '../../views/widgets/app_snackbar.dart';
import 'photo_model.dart';
import 'photo_capture_viewmodel.dart';

/// Shared style for Capture Photo screen buttons (matches Generate Photo Continue).
ButtonStyle captureScreenButtonStyle({bool secondary = false}) {
  return ElevatedButton.styleFrom(
    backgroundColor: secondary ? Colors.grey : Colors.blue,
    foregroundColor: Colors.white,
    disabledBackgroundColor: Colors.grey.shade600,
    disabledForegroundColor: Colors.white70,
    minimumSize: const Size(double.infinity, 56),
    padding: const EdgeInsets.symmetric(vertical: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
  );
}

/// Retake: clear the still and return to live preview.
///
/// Always clears local capture state first. On web we used to only
/// [pushReplacementNamed] without clearing — when Flutter reused the same
/// route State, the phone/gallery still stayed on screen.
///
/// Pass [routeArguments] so web replace keeps [CaptureRouteArgs] (e.g.
/// FotoFlashback multi-shot). Set [skipWebRouteReplace] when the caller must
/// keep the current State (strip progress lives on the screen State).
Future<void> handleCapturedPhotoRetake({
  required BuildContext context,
  required CaptureViewModel viewModel,
  required bool Function() isMounted,
  Object? routeArguments,
  bool skipWebRouteReplace = false,
}) async {
  await viewModel.clearCapturedPhotoAwaitingSession();
  if (kIsWeb && !skipWebRouteReplace) {
    await viewModel.disposeCamera();
    if (!isMounted() || !context.mounted) return;
    await Navigator.of(context).pushReplacementNamed(
      AppConstants.kRouteCapture,
      arguments: routeArguments,
    );
  }
}

/// Continue: upload, navigate to theme selection; release cameras in parallel.
///
/// When [returnPhotoOnly] is true (FotoFlashback multi-shot), skip session
/// upload and pop with the [PhotoModel] for the caller to collect.
Future<void> handleCapturedPhotoContinue({
  required BuildContext context,
  required CaptureViewModel viewModel,
  required bool Function() isMounted,
  Future<void> Function()? releaseCaptureHardware,
  bool returnPhotoOnly = false,
}) async {
  if (!viewModel.canContinueUpload || viewModel.isUploading) return;
  final currentContext = context;
  if (!isMounted() || !currentContext.mounted) return;

  if (returnPhotoOnly) {
    final photo = viewModel.capturedPhoto;
    if (photo == null) return;
    final releaseFuture = _startCaptureHardwareRelease(
      viewModel: viewModel,
      releaseCaptureHardware: releaseCaptureHardware,
    );
    await _finishReturnPhotoOnly(
      context: currentContext,
      viewModel: viewModel,
      isMounted: isMounted,
      releaseFuture: releaseFuture,
    );
    return;
  }

  // Encode + PATCH before native UVC/CameraX teardown. Parallel release used to
  // block the platform thread during readAsBytes/compute and freeze this loader.
  final success = await viewModel.uploadPhotoToSession();
  if (!isMounted() || !currentContext.mounted) return;
  if (!success || viewModel.capturedPhoto == null) {
    if (viewModel.hasError && currentContext.mounted) {
      AppSnackBar.showError(
        currentContext,
        viewModel.errorMessage ?? 'Failed to upload photo',
      );
    }
    return;
  }
  final releaseFuture = _startCaptureHardwareRelease(
    viewModel: viewModel,
    releaseCaptureHardware: releaseCaptureHardware,
  );
  try {
    await releaseFuture.timeout(const Duration(seconds: 4));
  } on TimeoutException {
    AppLogger.error('releaseCaptureHardware timed out before leaving POSE');
  } catch (e, st) {
    AppLogger.error(
      'releaseCaptureHardware failed before leaving POSE',
      error: e,
      stackTrace: st,
    );
  }
  if (!isMounted() || !currentContext.mounted) return;
  final photo = viewModel.capturedPhoto!;
  if (!isMounted() || !currentContext.mounted) return;
  final eventCapture = await EventManager().isEventBound() &&
      await EventManager().getStationRole() == EventStationRole.capture;
  if (!isMounted() || !currentContext.mounted) return;
  WebFlowTrace.log('NAV', 'pushReplacementNamed after capture start');
  await Navigator.of(currentContext, rootNavigator: true).pushReplacementNamed(
    resolvePostCaptureRoute(eventCaptureStation: eventCapture),
    arguments: eventCapture ? null : ThemeSelectionArgs(photo: photo),
  );
  WebFlowTrace.log('NAV', 'pushReplacementNamed done');
}

Future<void> _startCaptureHardwareRelease({
  required CaptureViewModel viewModel,
  Future<void> Function()? releaseCaptureHardware,
}) {
  final releaseFuture = releaseCaptureHardware != null
      ? releaseCaptureHardware()
      : viewModel.disposeCamera();
  UvcSessionCoordinator.trackTeardown(releaseFuture);
  unawaited(
    releaseFuture.catchError((Object e, StackTrace st) {
      AppLogger.error(
        'releaseCaptureHardware failed during continue',
        error: e,
        stackTrace: st,
      );
    }),
  );
  return releaseFuture;
}

Future<void> _finishReturnPhotoOnly({
  required BuildContext context,
  required CaptureViewModel viewModel,
  required bool Function() isMounted,
  required Future<void> releaseFuture,
}) async {
  final photo = viewModel.capturedPhoto;
  if (photo == null) return;
  try {
    await releaseFuture.timeout(const Duration(seconds: 4));
  } on TimeoutException {
    AppLogger.error('releaseCaptureHardware timed out (returnPhotoOnly)');
  } catch (e, st) {
    AppLogger.error(
      'releaseCaptureHardware failed (returnPhotoOnly)',
      error: e,
      stackTrace: st,
    );
  }
  if (!isMounted() || !context.mounted) return;
  Navigator.of(context).pop<PhotoModel>(photo);
}
