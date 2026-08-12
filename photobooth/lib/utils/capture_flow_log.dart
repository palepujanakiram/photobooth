import '../services/error_reporting/error_reporting_manager.dart';
import 'logger.dart';
import 'web_flow_trace.dart';

/// Structured capture / Classic strip events for console + Bugsnag breadcrumbs.
///
/// Use stable dotted [name]s (`capture.shutter_begin`, `classic.shot_accept`)
/// so filters work across Classic and FotoZen. Keep [fields] small — no base64,
/// JPEG bodies, or PII.
class CaptureFlowLog {
  CaptureFlowLog._();

  /// Test-only: exercises the private constructor for coverage.
  static void touchPrivateConstructorForTests() => CaptureFlowLog._();

  /// Emit one phase event to [AppLogger] and Bugsnag breadcrumbs.
  ///
  /// When [webFlow] is true, also appends to [WebFlowTrace] (HUD / DevTools).
  static void event(
    String name, {
    Map<String, Object?> fields = const {},
    LogLevel level = LogLevel.info,
    bool webFlow = false,
  }) {
    final detail = formatFields(fields);
    final message = detail.isEmpty ? name : '$name $detail';
    switch (level) {
      case LogLevel.debug:
        AppLogger.debug(message);
      case LogLevel.info:
        AppLogger.info(message);
      case LogLevel.warning:
        AppLogger.warning(message);
      case LogLevel.error:
        AppLogger.error(message, report: false);
    }
    ErrorReportingManager.log(message);
    if (webFlow) {
      WebFlowTrace.log(name, detail);
    }
  }

  /// Compact `k=v` pairs for logs (skips null / empty).
  static String formatFields(Map<String, Object?> fields) {
    if (fields.isEmpty) return '';
    final parts = <String>[];
    for (final entry in fields.entries) {
      final value = entry.value;
      if (value == null) continue;
      final text = value is String ? value.trim() : '$value';
      if (text.isEmpty) continue;
      parts.add('${entry.key}=$text');
    }
    return parts.join(' ');
  }
}
