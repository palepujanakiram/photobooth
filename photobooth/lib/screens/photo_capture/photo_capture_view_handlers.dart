import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../../utils/route_args.dart';
import '../../utils/web_flow_trace.dart';
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

/// Retake: on web replaces the route; elsewhere clears the captured still.
Future<void> handleCapturedPhotoRetake({
  required BuildContext context,
  required CaptureViewModel viewModel,
  required bool Function() isMounted,
}) async {
  if (kIsWeb) {
    await viewModel.disposeCamera();
    if (!isMounted() || !context.mounted) return;
    await Navigator.of(context).pushReplacementNamed(
      AppConstants.kRouteCapture,
    );
    return;
  }
  viewModel.clearCapturedPhoto();
}

/// Continue: release cameras, upload, navigate to theme selection.
Future<void> handleCapturedPhotoContinue({
  required BuildContext context,
  required CaptureViewModel viewModel,
  required bool Function() isMounted,
  Future<void> Function()? releaseCaptureHardware,
}) async {
  if (!viewModel.canContinueUpload || viewModel.isUploading) return;
  final currentContext = context;
  if (!isMounted() || !currentContext.mounted) return;

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

  if (releaseCaptureHardware != null) {
    await releaseCaptureHardware();
  } else {
    await viewModel.disposeCamera();
  }
  final photo = viewModel.capturedPhoto!;
  if (!isMounted() || !currentContext.mounted) return;
  WebFlowTrace.log('NAV', 'pushReplacementNamed theme-selection start');
  await Navigator.of(currentContext, rootNavigator: true).pushReplacementNamed(
    AppConstants.kRouteHome,
    arguments: ThemeSelectionArgs(photo: photo),
  );
  WebFlowTrace.log('NAV', 'pushReplacementNamed done');
}
