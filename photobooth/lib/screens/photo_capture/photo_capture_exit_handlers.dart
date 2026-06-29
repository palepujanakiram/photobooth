import 'package:flutter/material.dart';

import '../../services/customer_session_lifecycle.dart';
import '../../utils/constants.dart';
import '../../utils/logger.dart';
import 'photo_capture_viewmodel.dart';

/// Releases CameraX and any UVC session owned by the capture screen.
Future<void> releaseCaptureScreenHardware({
  required Future<void> Function() disposeUvc,
  required CaptureViewModel viewModel,
}) async {
  await disposeUvc();
  await viewModel.disposeCamera();
}

/// Ends the customer session, releases camera hardware, and returns to Terms.
Future<void> exitCaptureScreenToTerms({
  required BuildContext context,
  required bool Function() isMounted,
  required Future<void> Function() releaseCaptureHardware,
  required String sessionEndContext,
  Future<void> Function(String context)? endSession,
}) async {
  if (!isMounted() || !context.mounted) return;

  AppLogger.debug('POSE exit → Terms ($sessionEndContext)');
  await releaseCaptureHardware();
  if (!isMounted() || !context.mounted) return;

  await (endSession ?? endPhotoboothCustomerSessionLogged)(sessionEndContext);
  if (!isMounted() || !context.mounted) return;

  await Navigator.of(context).pushReplacementNamed(AppConstants.kRouteTerms);
}
