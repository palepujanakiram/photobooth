import 'dart:async' show unawaited;

import 'package:dio/dio.dart';

import '../services/error_reporting/error_reporting_manager.dart';
import 'exceptions.dart';
import 'logger.dart';

/// Whether [error] should be forwarded to Bugsnag.
///
/// Skips errors already reported elsewhere (e.g. [DioException] in
/// [ApiLoggingInterceptor]) and known non-fatal noise (image decode, face count).
bool shouldAutoReportError(Object error, String message) {
  if (error is DioException) return false;
  if (error is ApiException) return false;

  final lower = message.toLowerCase();
  if (lower.contains('face count')) return false;
  if (lower.contains('network image') || lower.contains('cachednetworkimage')) {
    return false;
  }
  if (lower.contains('staff logout') || lower.contains('logged out')) {
    return false;
  }
  return true;
}

/// Sends [error] to Bugsnag when [shouldAutoReportError] allows it.
void maybeAutoReportError(
  String reason,
  Object error,
  StackTrace? stackTrace, {
  Map<String, dynamic>? extraInfo,
  bool fatal = false,
}) {
  if (!shouldAutoReportError(error, reason)) return;
  unawaited(
    ErrorReportingManager.recordError(
      error,
      stackTrace ?? StackTrace.current,
      reason: reason,
      extraInfo: extraInfo,
      fatal: fatal,
    ),
  );
}

/// Logs an issue and reports it to Bugsnag (unless filtered).
Future<void> reportIssue(
  String reason,
  Object error,
  StackTrace stackTrace, {
  Map<String, dynamic>? extraInfo,
  bool fatal = false,
}) async {
  AppLogger.error(reason, error: error, stackTrace: stackTrace, report: false);
  if (!shouldAutoReportError(error, reason)) return;
  await ErrorReportingManager.recordError(
    error,
    stackTrace,
    reason: reason,
    extraInfo: extraInfo,
    fatal: fatal,
  );
}
