import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../../utils/route_args.dart';
import '../../utils/web_flow_trace.dart';
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
    viewModel.disposeCamera();
    if (!isMounted()) return;
    await Navigator.of(context).pushReplacementNamed(
      AppConstants.kRouteCapture,
    );
    return;
  }
  viewModel.clearCapturedPhoto();
}

/// Continue: upload, release camera, navigate to theme selection.
Future<void> handleCapturedPhotoContinue({
  required BuildContext context,
  required CaptureViewModel viewModel,
  required bool Function() isMounted,
}) async {
  if (viewModel.isCapturing || viewModel.isUploading) return;
  final currentContext = context;
  if (!isMounted() || !currentContext.mounted) return;
  final success = await viewModel.uploadPhotoToSession();
  if (!isMounted() || !currentContext.mounted) return;
  if (!success || viewModel.capturedPhoto == null) return;

  viewModel.disposeCamera();
  final photo = viewModel.capturedPhoto!;
  if (!isMounted() || !currentContext.mounted) return;
  WebFlowTrace.log('NAV', 'pushReplacementNamed theme-selection start');
  await Navigator.of(currentContext, rootNavigator: true).pushReplacementNamed(
    AppConstants.kRouteHome,
    arguments: ThemeSelectionArgs(photo: photo),
  );
  WebFlowTrace.log('NAV', 'pushReplacementNamed done');
}
