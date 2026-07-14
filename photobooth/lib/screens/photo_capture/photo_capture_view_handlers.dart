import 'dart:async' show TimeoutException, unawaited;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../services/uvc_session_coordinator.dart';
import '../../utils/constants.dart';
import '../../utils/route_args.dart';
import '../../utils/web_flow_trace.dart';
import '../../utils/logger.dart';
import '../../views/widgets/app_snackbar.dart';
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
Future<void> handleCapturedPhotoRetake({
  required BuildContext context,
  required CaptureViewModel viewModel,
  required bool Function() isMounted,
}) async {
  await viewModel.clearCapturedPhotoAwaitingSession();
  if (kIsWeb) {
    await viewModel.disposeCamera();
    if (!isMounted() || !context.mounted) return;
    await Navigator.of(context).pushReplacementNamed(
      AppConstants.kRouteCapture,
    );
  }
}

/// Continue: upload, navigate to theme selection; release cameras in parallel.
Future<void> handleCapturedPhotoContinue({
  required BuildContext context,
  required CaptureViewModel viewModel,
  required bool Function() isMounted,
  Future<void> Function()? releaseCaptureHardware,
}) async {
  if (!viewModel.canContinueUpload || viewModel.isUploading) return;
  final currentContext = context;
  if (!isMounted() || !currentContext.mounted) return;

  // Paint "Processing…" before any await — native UVC teardown can block the
  // platform thread long enough to look like a freeze while still on "Preparing…".
  viewModel.beginContinueUpload();
  await Future<void>.delayed(Duration.zero);
  if (!isMounted() || !currentContext.mounted) return;

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

  final success = await viewModel.uploadPhotoToSession(uploadAlreadyStarted: true);
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
  WebFlowTrace.log('NAV', 'pushReplacementNamed theme-selection start');
  await Navigator.of(currentContext, rootNavigator: true).pushReplacementNamed(
    AppConstants.kRouteHome,
    arguments: ThemeSelectionArgs(photo: photo),
  );
  WebFlowTrace.log('NAV', 'pushReplacementNamed done');
}
