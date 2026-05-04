/// Utilities for truncation and human-readable sizes/durations.
class LogTruncator {
  const LogTruncator({
    this.maxLoggedJsonLength = 6000,
  });

  final int maxLoggedJsonLength;

  String truncateJson(String jsonString) {
    if (jsonString.length > maxLoggedJsonLength) {
      return '${jsonString.substring(0, maxLoggedJsonLength)}... '
          '[truncated, ${jsonString.length} chars total]';
    }
    return jsonString;
  }

  String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String formatDuration(Duration duration) {
    if (duration.inSeconds < 1) {
      return '${duration.inMilliseconds}ms';
    } else if (duration.inSeconds < 60) {
      final fraction = (duration.inMilliseconds % 1000)
          .toString()
          .padLeft(3, '0')
          .substring(0, 2);
      return '${duration.inSeconds}.$fraction' 's';
    } else {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    }
  }
}

