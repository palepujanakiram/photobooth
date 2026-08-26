import 'dart:developer' as developer;
import 'package:flutter/foundation.dart'
    show ValueListenable, debugPrint, kIsWeb, visibleForTesting;

import 'coalesced_string_list_notifier.dart';
import 'constants.dart';
import 'error_reporting_helpers.dart';
import 'logger_stack_frame.dart';

/// Log levels matching CocoaLumberjack-style logging
enum LogLevel {
  debug(0, 'DEBUG'),
  info(800, 'INFO'),
  warning(900, 'WARNING'),
  error(1000, 'ERROR');

  final int value;
  final String label;
  const LogLevel(this.value, this.label);
}

/// A CocoaLumberjack-style logging utility that uses Flutter's recommended `dart:developer` log.
class AppLogger {
  static const int _maxBufferedLines = 250;
  static final CoalescedStringListNotifier _recentLinesBuffer =
      CoalescedStringListNotifier(maxLines: _maxBufferedLines);

  static ValueListenable<List<String>> get recentLinesListenable =>
      _recentLinesBuffer.lines;

  static void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    // Stack walks are costly on web when logging is very chatty during upload.
    final fileInfo = kIsWeb
        ? 'web'
        : (parseLoggerCallSite(StackTrace.current)?.location ?? 'unknown');
    final formattedMessage = '[${level.label}] $fileInfo - $message';
    final logToConsole = AppConstants.kEnableLogOutput;
    final logToHud = AppConstants.kShowDebugHud;
    if (!logToConsole && !logToHud) return;

    if (logToHud) {
      _appendToRingBuffer(
        formattedMessage,
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (!logToConsole) return;

    developer.log(
      formattedMessage,
      name: 'AppLogger',
      level: level.value,
      error: error,
      stackTrace: stackTrace,
    );

    // `developer.log` alone is invisible on a booth. It is delivered to the VM
    // service — DevTools, `flutter logs`, `flutter attach` — and never to stdout,
    // so `adb logcat` shows nothing: a kiosk in the field logged for an hour and
    // produced zero AppLogger lines, which is why a print that failed somewhere in
    // Dart could not be diagnosed at all.
    //
    // `debugPrint` reaches stdout, so the same line lands in logcat under
    // `I/flutter`. Both are kept: the structured record stays available to
    // DevTools, at the cost of a duplicate line when someone runs `flutter run`.
    // Reading a booth over adb is the case that actually matters.
    if (!kIsWeb) {
      _mirrorToConsole(formattedMessage, error: error, stackTrace: stackTrace);
    }
  }

  /// Set false to silence the logcat mirror (keeps test output readable).
  @visibleForTesting
  static bool mirrorLogsToConsole = true;

  static void _mirrorToConsole(
    String formattedMessage, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!mirrorLogsToConsole) return;
    debugPrint(formattedMessage);
    if (error != null) debugPrint('  error: $error');
    if (stackTrace != null) debugPrint('  $stackTrace');
  }

  static void _appendToRingBuffer(
    String formattedMessage, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    const maxBufferedChars = 2048;
    final forBuffer = formattedMessage.length > maxBufferedChars
        ? '${formattedMessage.substring(0, maxBufferedChars)}… '
            '[+${formattedMessage.length - maxBufferedChars} chars]'
        : formattedMessage;

    _recentLinesBuffer.appendAll(<String>[
      forBuffer,
      if (error != null) '    ↳ error: $error',
      if (stackTrace != null)
        '    ↳ stack: ${stackTrace.toString().split('\n').first}',
    ]);
  }

  static void debug(String message, {Object? error, StackTrace? stackTrace}) {
    log(LogLevel.debug, message, error: error, stackTrace: stackTrace);
  }

  static void info(String message, {Object? error, StackTrace? stackTrace}) {
    log(LogLevel.info, message, error: error, stackTrace: stackTrace);
  }

  static void warning(String message, {Object? error, StackTrace? stackTrace}) {
    log(LogLevel.warning, message, error: error, stackTrace: stackTrace);
  }

  static void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    bool report = true,
  }) {
    log(LogLevel.error, message, error: error, stackTrace: stackTrace);
    if (report && error != null) {
      maybeAutoReportError(message, error, stackTrace);
    }
  }
}
