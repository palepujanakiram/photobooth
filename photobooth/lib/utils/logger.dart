import 'dart:developer' as developer;
import 'package:flutter/foundation.dart' show ValueListenable, kIsWeb;

import 'coalesced_string_list_notifier.dart';
import 'constants.dart';
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

  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    log(LogLevel.error, message, error: error, stackTrace: stackTrace);
  }
}
