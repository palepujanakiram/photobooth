/// Point-in-time device / process memory readings for low-RAM detection.
class DeviceMemorySnapshot {
  const DeviceMemorySnapshot({
    this.processRssBytes,
    this.availableSystemBytes,
    this.totalSystemBytes,
    this.systemLowMemoryFlag = false,
  });

  final int? processRssBytes;
  final int? availableSystemBytes;
  final int? totalSystemBytes;
  final bool systemLowMemoryFlag;

  Map<String, dynamic> toExtraInfo({required String trigger}) {
    return {
      'trigger': trigger,
      'process_rss_mb': _mb(processRssBytes),
      'available_system_mb': _mb(availableSystemBytes),
      'total_system_mb': _mb(totalSystemBytes),
      'system_low_memory_flag': systemLowMemoryFlag.toString(),
    };
  }

  static String? _mb(int? bytes) {
    if (bytes == null) return null;
    return (bytes / (1024 * 1024)).toStringAsFixed(1);
  }
}
