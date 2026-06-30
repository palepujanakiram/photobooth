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

/// Releases camera hardware and returns to Terms.
///
/// When [endCustomerSession] is true (idle timeout), clears the customer session
/// before navigation. Back navigation keeps the session so the guest can re-enter
/// capture without creating a new session.
Future<void> exitCaptureScreenToTerms({
  required BuildContext context,
  required bool Function() isMounted,
  required Future<void> Function() releaseCaptureHardware,
  required String sessionEndContext,
  Future<void> Function(String context)? endSession,
  bool endCustomerSession = true,
}) async {
  if (!isMounted() || !context.mounted) return;

  AppLogger.debug('POSE exit → Terms ($sessionEndContext)');
  try {
    await releaseCaptureHardware();
  } catch (e, st) {
    AppLogger.error(
      'POSE hardware release failed ($sessionEndContext)',
      error: e,
      stackTrace: st,
    );
  }
  if (!isMounted() || !context.mounted) return;

  if (endCustomerSession) {
    await (endSession ?? endPhotoboothCustomerSessionLogged)(sessionEndContext);
    if (!isMounted() || !context.mounted) return;
  }

  await Navigator.of(context).pushReplacementNamed(AppConstants.kRouteTerms);
}
