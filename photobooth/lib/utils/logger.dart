import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

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
  static final ValueNotifier<List<String>> _recentLines =
      ValueNotifier<List<String>>(<String>[]);

  static ValueListenable<List<String>> get recentLinesListenable => _recentLines;

  static void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final site = parseLoggerCallSite(StackTrace.current);
    final fileInfo = site?.location ?? 'unknown';
    final formattedMessage = '[${level.label}] $fileInfo - $message';
    _appendToRingBuffer(formattedMessage, error: error, stackTrace: stackTrace);

    if (AppConstants.kEnableLogOutput) {
      developer.log(
        formattedMessage,
        name: 'AppLogger',
        level: level.value,
        error: error,
        stackTrace: stackTrace,
      );
    }
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

    final current = _recentLines.value;
    final next = <String>[
      ...current,
      forBuffer,
      if (error != null) '    ↳ error: $error',
      if (stackTrace != null)
        '    ↳ stack: ${stackTrace.toString().split('\n').first}',
    ];
    _recentLines.value = next.length > _maxBufferedLines
        ? next.sublist(next.length - _maxBufferedLines)
        : next;
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
