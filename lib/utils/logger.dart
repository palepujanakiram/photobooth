import 'dart:developer' as developer;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'constants.dart';

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
/// 
/// Automatically captures file name, function name, and line number from the call site.
/// 
/// Usage:
/// ```dart
/// AppLogger.log(LogLevel.debug, 'This is a debug message');
/// AppLogger.log(LogLevel.info, 'User logged in');
/// AppLogger.log(LogLevel.warning, 'Low memory warning');
/// AppLogger.log(LogLevel.error, 'Failed to load data');
/// 
/// // Or use convenience methods:
/// AppLogger.debug('Debug message');
/// AppLogger.info('Info message');
/// AppLogger.warning('Warning message');
/// AppLogger.error('Error message');
/// ```
class AppLogger {
  /// Main logging function that takes log level and message
  /// Automatically extracts file name, function name, and line number from stack trace
  static void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    // Get the caller's stack frame (skip this function and the convenience methods)
    final currentStackTrace = StackTrace.current;
    final frames = currentStackTrace.toString().split('\n');
    
    // Find the first frame that's not from this logger file
    // Usually frame 2 or 3 (0 = this function, 1 = convenience method if used, 2+ = actual caller)
    String? fileName;
    String? functionName;
    String? lineNumber;
    
    for (int i = 0; i < frames.length && i < 5; i++) {
      final frame = frames[i];
      if (frame.contains('logger.dart')) {
        continue; // Skip logger internal frames
      }
      
      // Parse stack frame: "package:path/file.dart 123:45  FunctionName"
      // Or: "#0      FunctionName (package:path/file.dart:123:45)"
      final match = RegExp(
        r'(?:#\d+\s+)?([\w<>]+)\s+\(([^:]+):(\d+):\d+\)|([^:]+):(\d+):\d+\s+([\w<>]+)',
      ).firstMatch(frame);
      
      if (match != null) {
        if (match.group(1) != null) {
          // Format: "#0 FunctionName (file.dart:123:45)"
          functionName = match.group(1);
          fileName = _extractFileName(match.group(2) ?? '');
          lineNumber = match.group(3);
        } else if (match.group(4) != null) {
          // Format: "file.dart:123:45 FunctionName"
          fileName = _extractFileName(match.group(4) ?? '');
          lineNumber = match.group(5);
          functionName = match.group(6);
        }
        
        if (fileName != null && !fileName.contains('logger.dart')) {
          break; // Found the actual caller
        }
      }
    }
    
    // Fallback: try simpler parsing
    if (fileName == null || functionName == null || lineNumber == null) {
      for (int i = 0; i < frames.length && i < 5; i++) {
        final frame = frames[i];
        if (frame.contains('logger.dart')) continue;
        
        // Try to extract at least file and line
        final fileMatch = RegExp(r'([^/\\]+\.dart):(\d+)').firstMatch(frame);
        if (fileMatch != null) {
          fileName = fileMatch.group(1);
          lineNumber = fileMatch.group(2);
          // Try to get function name
          final funcMatch = RegExp(r'(\w+)\s*\([^)]*\)').firstMatch(frame);
          functionName = funcMatch?.group(1) ?? 'unknown';
          break;
        }
      }
    }
    
    // Format the log message similar to CocoaLumberjack
    // Format: [LEVEL] fileName:functionName:lineNumber - message
    final fileInfo = fileName != null && functionName != null && lineNumber != null
        ? '${_extractFileName(fileName)}:$functionName:$lineNumber'
        : 'unknown';
    
    final formattedMessage = '[${level.label}] $fileInfo - $message';
    
    if (AppConstants.kEnableLogOutput) {
      developer.log(
        formattedMessage,
        name: 'AppLogger',
        level: level.value,
        error: error,
        stackTrace: stackTrace,
      );
    }
    
    // Send errors and warnings to Firebase Crashlytics (if available)
    if (level == LogLevel.error || level == LogLevel.warning) {
      _sendToCrashlytics(formattedMessage, error, stackTrace);
    } else if (AppConstants.kEnableLogOutput) {
      // For debug and info logs, just log as breadcrumbs (if available)
      _logToCrashlytics(formattedMessage);
    }
  }
  
  /// Send error to Crashlytics if available
  static void _sendToCrashlytics(String message, Object? error, StackTrace? stackTrace) {
    try {
      // Check if Firebase is available before using it
      FirebaseCrashlytics.instance.recordError(
        error ?? Exception(message),
        stackTrace,
        reason: message,
        fatal: false,
      );
      FirebaseCrashlytics.instance.log(message);
    } catch (e) {
      // Silently ignore if Firebase/Crashlytics not initialized
      // This allows the app to work without Crashlytics
    }
  }
  
  /// Log breadcrumb to Crashlytics if available
  static void _logToCrashlytics(String message) {
    try {
      FirebaseCrashlytics.instance.log(message);
    } catch (e) {
      // Silently ignore if Firebase/Crashlytics not initialized
    }
  }
  
  /// Extract just the file name from a full path
  static String _extractFileName(String path) {
    if (path.isEmpty) return 'unknown';
    // Remove package: prefix if present
    path = path.replaceFirst(RegExp(r'^package:[^/]+/'), '');
    // Get just the filename
    final parts = path.split(RegExp(r'[/\\]'));
    return parts.isNotEmpty ? parts.last : path;
  }
  
  /// Convenience method for debug level logging
  /// File name, function name, and line number are automatically extracted
  static void debug(String message, {Object? error, StackTrace? stackTrace}) {
    log(LogLevel.debug, message, error: error, stackTrace: stackTrace);
  }
  
  /// Convenience method for info level logging
  /// File name, function name, and line number are automatically extracted
  static void info(String message, {Object? error, StackTrace? stackTrace}) {
    log(LogLevel.info, message, error: error, stackTrace: stackTrace);
  }
  
  /// Convenience method for warning level logging
  /// File name, function name, and line number are automatically extracted
  static void warning(String message, {Object? error, StackTrace? stackTrace}) {
    log(LogLevel.warning, message, error: error, stackTrace: stackTrace);
  }
  
  /// Convenience method for error level logging
  /// File name, function name, and line number are automatically extracted
  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    log(LogLevel.error, message, error: error, stackTrace: stackTrace);
  }
}
