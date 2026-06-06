import 'app_strings.dart';

/// Parsed call-site metadata for [AppLogger].
class LoggerCallSite {
  const LoggerCallSite({
    required this.fileName,
    required this.functionName,
    required this.lineNumber,
  });

  final String fileName;
  final String functionName;
  final String lineNumber;

  String get location => '$fileName:$functionName:$lineNumber';
}

LoggerCallSite? parseLoggerCallSite(StackTrace stackTrace) {
  final frames = stackTrace.toString().split('\n');
  for (var i = 0; i < frames.length && i < 5; i++) {
    final frame = frames[i];
    if (frame.contains(AppStrings.loggerFileName)) continue;
    final parsed = _parseFrame(frame);
    if (parsed != null &&
        !parsed.fileName.contains(AppStrings.loggerFileName)) {
      return parsed;
    }
  }
  return _parseFallbackFrame(frames);
}

LoggerCallSite? _parseFrame(String frame) {
  final match = RegExp(
    r'(?:#\d+\s+)?([\w<>]+)\s+\(([^:]+):(\d+):\d+\)|([^:]+):(\d+):\d+\s+([\w<>]+)',
  ).firstMatch(frame);
  if (match == null) return null;

  if (match.group(1) != null) {
    return LoggerCallSite(
      fileName: _fileNameOnly(match.group(2) ?? ''),
      functionName: match.group(1)!,
      lineNumber: match.group(3) ?? '?',
    );
  }
  return LoggerCallSite(
    fileName: _fileNameOnly(match.group(4) ?? ''),
    functionName: match.group(6) ?? 'unknown',
    lineNumber: match.group(5) ?? '?',
  );
}

LoggerCallSite? _parseFallbackFrame(List<String> frames) {
  for (var i = 0; i < frames.length && i < 5; i++) {
    final frame = frames[i];
    if (frame.contains(AppStrings.loggerFileName)) continue;
    final fileMatch = RegExp(r'([^/\\]+\.dart):(\d+)').firstMatch(frame);
    if (fileMatch == null) continue;
    final funcMatch = RegExp(r'(\w+)\s*\([^)]*\)').firstMatch(frame);
    return LoggerCallSite(
      fileName: fileMatch.group(1) ?? 'unknown',
      functionName: funcMatch?.group(1) ?? 'unknown',
      lineNumber: fileMatch.group(2) ?? '?',
    );
  }
  return null;
}

String _fileNameOnly(String path) {
  if (path.isEmpty) return 'unknown';
  final normalized = path.replaceFirst(RegExp(r'^package:[^/]+/'), '');
  final parts = normalized.split(RegExp(r'[/\\]'));
  return parts.isNotEmpty ? parts.last : normalized;
}
