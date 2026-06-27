import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

import '../models/device_memory_snapshot.dart';
import '../utils/constants.dart';
import '../utils/device_memory_info.dart';
import '../utils/logger.dart';
import 'error_reporting/error_reporting_manager.dart';

/// Payload passed to [LowMemoryMonitor.reportHandler] in tests.
class LowMemoryReport {
  const LowMemoryReport({
    required this.reasonKey,
    required this.reason,
    required this.snapshot,
    required this.trigger,
  });

  final String reasonKey;
  final String reason;
  final DeviceMemorySnapshot snapshot;
  final String trigger;
}

/// Polls device memory and reports low-RAM conditions to Bugsnag (deduped).
class LowMemoryMonitor {
  LowMemoryMonitor({
    Future<DeviceMemorySnapshot> Function()? readSnapshot,
    DateTime Function()? now,
    this.dedupeWindow = const Duration(minutes: 5),
    this.pollInterval = const Duration(seconds: 30),
    this.reportHandler,
  }) : _readSnapshot = readSnapshot ?? readDeviceMemorySnapshot,
       _now = now ?? DateTime.now;

  static final LowMemoryMonitor instance = LowMemoryMonitor();

  /// Primary target: 4 GB RAM Android kiosks.
  static const int targetKioskRamBytes = 4 * 1024 * 1024 * 1024;

  /// Devices at or above this reported total RAM use [minAvailableSystemBytes4Gb].
  static const int fourGbClassMinTotalBytes = 3500 * 1024 * 1024;

  /// Alert when free system RAM drops below ~10% on a 4 GB kiosk (400 MB).
  static const int minAvailableSystemBytes4Gb = 400 * 1024 * 1024;

  /// Alert when app RSS exceeds ~800 MB during camera / upload on 4 GB kiosks.
  static const int maxProcessRssBytes4Gb = 800 * 1024 * 1024;

  /// Fallback for smaller/unknown devices when total RAM is not reported.
  static const int minAvailableSystemBytesDefault = 250 * 1024 * 1024;

  /// Fallback RSS ceiling for sub-4 GB devices (~2–3 GB class).
  static const int maxProcessRssBytesDefault = 500 * 1024 * 1024;

  /// Tighter limits when [AppConstants.kLowMemoryKioskMode] is active (~2 GB TV boxes).
  static const int minAvailableSystemBytesLowRamKiosk = 150 * 1024 * 1024;
  static const int maxProcessRssBytesLowRamKiosk = 350 * 1024 * 1024;

  final Future<DeviceMemorySnapshot> Function() _readSnapshot;
  final DateTime Function() _now;
  final Duration dedupeWindow;
  final Duration pollInterval;

  @visibleForTesting
  final Future<void> Function(LowMemoryReport report)? reportHandler;

  Timer? _pollTimer;
  final Map<String, DateTime> _lastReportedAt = {};

  void start() {
    if (kIsWeb) return;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) {
      unawaited(_poll());
    });
    unawaited(_poll());
  }

  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void onMemoryPressure() {
    if (kIsWeb) return;
    unawaited(
      _readSnapshot().then(
        (snapshot) => evaluate(snapshot, trigger: 'memory_pressure'),
      ),
    );
  }

  Future<void> _poll() async {
    try {
      final snapshot = await _readSnapshot();
      await evaluate(snapshot, trigger: 'poll');
    } catch (e, st) {
      AppLogger.debug('LowMemoryMonitor poll failed: $e\n$st');
    }
  }

  /// Returns dedupe keys for issues detected in [snapshot].
  @visibleForTesting
  List<String> detectIssueKeys(
    DeviceMemorySnapshot snapshot, {
    required String trigger,
  }) {
    if (trigger == 'memory_pressure') {
      return const ['os_memory_pressure'];
    }

    final keys = <String>[];
    if (snapshot.systemLowMemoryFlag) {
      keys.add('system_low_memory_flag');
    }
    final available = snapshot.availableSystemBytes;
    final minAvailable = minAvailableBytesFor(snapshot);
    if (available != null && available < minAvailable) {
      keys.add('system_available_below_threshold');
    }
    final rss = snapshot.processRssBytes;
    if (rss != null) {
      final maxRss = maxProcessRssFor(snapshot);
      if (rss > maxRss) {
        keys.add('process_rss_above_threshold');
      }
    }
    return keys;
  }

  /// Resolved free-RAM floor for [snapshot] (4 GB kiosk vs smaller/legacy devices).
  @visibleForTesting
  int minAvailableBytesFor(DeviceMemorySnapshot snapshot) {
    if (AppConstants.kLowMemoryKioskMode) {
      return minAvailableSystemBytesLowRamKiosk;
    }
    final total = snapshot.totalSystemBytes;
    if (total == null || total >= fourGbClassMinTotalBytes) {
      return minAvailableSystemBytes4Gb;
    }
    return minAvailableSystemBytesDefault;
  }

  /// Resolved process RSS ceiling for [snapshot].
  @visibleForTesting
  int maxProcessRssFor(DeviceMemorySnapshot snapshot) {
    if (AppConstants.kLowMemoryKioskMode) {
      return maxProcessRssBytesLowRamKiosk;
    }
    final total = snapshot.totalSystemBytes;
    if (total == null || total >= fourGbClassMinTotalBytes) {
      return maxProcessRssBytes4Gb;
    }
    return maxProcessRssBytesDefault;
  }

  Future<void> evaluate(
    DeviceMemorySnapshot snapshot, {
    required String trigger,
  }) async {
    for (final key in detectIssueKeys(snapshot, trigger: trigger)) {
      await _reportOnce(
        reasonKey: key,
        snapshot: snapshot,
        trigger: trigger,
        reason: _reasonForKey(key),
      );
    }
  }

  String _reasonForKey(String key) {
    switch (key) {
      case 'os_memory_pressure':
        return 'OS reported memory pressure';
      case 'system_low_memory_flag':
        return 'System low-memory flag set';
      case 'system_available_below_threshold':
        return 'System available memory below threshold';
      case 'process_rss_above_threshold':
        return 'Process RSS above threshold';
      default:
        return 'Device memory low';
    }
  }

  /// Exposed for unit tests (covers the default [_reasonForKey] branch).
  @visibleForTesting
  String reasonForKey(String key) => _reasonForKey(key);

  Future<void> _reportOnce({
    required String reasonKey,
    required DeviceMemorySnapshot snapshot,
    required String trigger,
    required String reason,
  }) async {
    final now = _now();
    final last = _lastReportedAt[reasonKey];
    if (last != null && now.difference(last) < dedupeWindow) {
      return;
    }
    _lastReportedAt[reasonKey] = now;

    final extraInfo = snapshot.toExtraInfo(trigger: trigger);
    extraInfo['reason_key'] = reasonKey;
    extraInfo['min_available_mb'] =
        (minAvailableBytesFor(snapshot) / (1024 * 1024)).toStringAsFixed(0);
    extraInfo['max_process_rss_mb'] =
        (maxProcessRssFor(snapshot) / (1024 * 1024)).toStringAsFixed(0);

    await ErrorReportingManager.setCustomKeys({
      'memory_process_rss_mb': extraInfo['process_rss_mb'] ?? 'unknown',
      'memory_available_mb': extraInfo['available_system_mb'] ?? 'unknown',
      'memory_trigger': trigger,
    });

    final report = LowMemoryReport(
      reasonKey: reasonKey,
      reason: reason,
      snapshot: snapshot,
      trigger: trigger,
    );
    final handler = reportHandler;
    if (handler != null) {
      await handler(report);
      return;
    }

    await ErrorReportingManager.recordError(
      StateError(reason),
      StackTrace.current,
      reason: reason,
      extraInfo: extraInfo,
    );
  }
}
