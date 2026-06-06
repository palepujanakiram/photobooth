// Global Flutter / async error hooks registered from main.
// Filters noisy image-decode failures (handled in UI) and forwards the rest
// to ErrorReportingManager (Bugsnag on mobile).
import 'package:flutter/foundation.dart';

import 'utils/constants.dart';
import 'utils/logger.dart';
import 'services/error_reporting/error_reporting_manager.dart';

/// True for known non-fatal image pipeline errors we already surface in widgets.
bool isFilteredImageError(Object error) {
  final errorString = error.toString().toLowerCase();
  return errorString.contains('image decoding') ||
      errorString.contains('failed to submit image decoding command buffer') ||
      errorString.contains('codec failed to produce an image') ||
      errorString.contains('failed to load network image');
}

/// Installs [FlutterError.onError] and [PlatformDispatcher.onError].
void configureFlutterErrorHandlers() {
  FlutterError.onError = (errorDetails) {
    if (isFilteredImageError(errorDetails.exception)) {
      if (kDebugMode) {
        AppLogger.error(
          'Image loading error (non-fatal, handled by UI): ${errorDetails.exception}',
          error: errorDetails.exception,
          stackTrace: errorDetails.stack,
        );
      }
      return;
    }

    ErrorReportingManager.recordError(
      errorDetails.exception,
      errorDetails.stack,
      reason: 'Flutter Fatal Error',
      fatal: true,
    );

    if (kDebugMode) {
      AppLogger.error(
        'Flutter Fatal Error: ${errorDetails.exception}',
        error: errorDetails.exception,
        stackTrace: errorDetails.stack,
      );
    }
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    if (isFilteredImageError(error)) {
      if (kDebugMode) {
        AppLogger.error(
          'Image loading error (non-fatal, handled by UI): $error',
          error: error,
          stackTrace: stack,
        );
      }
      return true;
    }

    ErrorReportingManager.recordError(
      error,
      stack,
      reason: 'Uncaught Async Error',
      fatal: true,
    );

    if (kDebugMode) {
      AppLogger.error(
        'Uncaught Error: $error',
        error: error,
        stackTrace: stack,
      );
    }
    return true;
  };
}

/// Debug-only log after [ErrorReportingManager.initialize].
void logErrorReportingReady() {
  if (!kDebugMode || !AppConstants.kEnableLogOutput) return;
  AppLogger.debug('✅ Error reporting initialized successfully');
  AppLogger.debug(
    'Active services: ${ErrorReportingManager.serviceCount} (Bugsnag: enabled)',
  );
}
