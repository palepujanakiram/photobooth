import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/android_process_exit.dart';
import '../utils/app_strings.dart';
import '../utils/logger.dart';
import '../utils/process_exit_info.dart';
import 'client_identification.dart';
import 'error_reporting/error_reporting_manager.dart';
import 'kiosk_manager.dart';

/// Injectable collaborators for [KioskHealthService] (keeps constructors ≤7 args).
class KioskHealthServiceDeps {
  const KioskHealthServiceDeps({
    this.readKioskCode,
    this.readExits,
    this.postHeartbeat,
    this.reportExit,
    this.readLastReportedExitMs,
    this.writeLastReportedExitMs,
    this.appVersion,
  });

  final Future<String?> Function()? readKioskCode;
  final Future<List<AndroidProcessExit>> Function()? readExits;
  final Future<void> Function(KioskHeartbeatRequest request)? postHeartbeat;
  final Future<void> Function(AndroidProcessExit exit)? reportExit;
  final Future<int> Function()? readLastReportedExitMs;
  final Future<void> Function(int timestampMs)? writeLastReportedExitMs;
  final String Function()? appVersion;
}

/// Body posted to `POST /api/kiosk/heartbeat`.
class KioskHeartbeatRequest {
  const KioskHeartbeatRequest({
    required this.kioskCode,
    required this.appVersion,
    required this.processExits,
  });

  final String kioskCode;
  final String appVersion;
  final List<AndroidProcessExit> processExits;
}

/// Periodic liveness + Android historical-exit reporting for TV kiosks.
///
/// Bugsnag never sees SIGKILL / LMK. This service:
/// 1. Reads [ApplicationExitInfo] on each ping and reports unexpected deaths.
/// 2. Heartbeats so a silent box is visible even if it never relaunches.
class KioskHealthService {
  KioskHealthService({
    KioskHealthServiceDeps? deps,
    this.heartbeatInterval = const Duration(seconds: 60),
    this.historyWindow = const Duration(hours: 24),
  }) : _deps = deps ?? const KioskHealthServiceDeps();

  static const String lastReportedExitPrefKey =
      'kiosk_health_last_reported_exit_ms';

  static final KioskHealthService instance = KioskHealthService();

  /// Production wiring (set from `main.dart`). Tests may replace this.
  static Future<void> Function(KioskHeartbeatRequest request)? sendHeartbeat;

  /// Clock for history-window math. Tests replace this.
  static DateTime Function() clock = DateTime.now;

  final KioskHealthServiceDeps _deps;
  final Duration heartbeatInterval;
  final Duration historyWindow;

  Timer? _timer;
  Future<void>? _inFlight;

  @visibleForTesting
  bool get isRunning => _timer != null;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(heartbeatInterval, (_) {
      unawaited(ping());
    });
    unawaited(ping());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> ping() {
    final existing = _inFlight;
    if (existing != null) return existing;
    final done = _pingBody().whenComplete(() {
      _inFlight = null;
    });
    _inFlight = done;
    return done;
  }

  Future<void> _pingBody() async {
    final code = (await _readKioskCode())?.trim().toUpperCase();
    if (code == null || code.isEmpty) return;

    final exits = await _newUnexpectedExits();
    for (final exit in exits) {
      await _reportExit(exit);
    }

    try {
      final post = _deps.postHeartbeat ?? sendHeartbeat;
      if (post == null) return;
      await post(
        KioskHeartbeatRequest(
          kioskCode: code,
          appVersion: _appVersion(),
          processExits: exits,
        ),
      );
      if (exits.isNotEmpty) {
        await _writeLastReportedExitMs(_maxTimestamp(exits));
      }
    } catch (e, st) {
      AppLogger.warning(
        AppStrings.kioskHeartbeatFailed,
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<List<AndroidProcessExit>> _newUnexpectedExits() async {
    final raw = await _readExits();
    final lastReported = await _readLastReportedExitMs();
    final cutoff = _now()
        .toUtc()
        .subtract(historyWindow)
        .millisecondsSinceEpoch;
    final minTs = lastReported > cutoff ? lastReported : cutoff;
    final selected = <AndroidProcessExit>[];
    for (final exit in raw) {
      if (!exit.isUnexpected) continue;
      if (exit.timestampMs <= minTs) continue;
      selected.add(exit);
    }
    selected.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    return selected;
  }

  Future<String?> _readKioskCode() {
    return (_deps.readKioskCode ?? KioskManager().getKioskCode)();
  }

  Future<List<AndroidProcessExit>> _readExits() {
    return (_deps.readExits ?? readHistoricalProcessExits)();
  }

  Future<void> _reportExit(AndroidProcessExit exit) {
    final report = _deps.reportExit;
    if (report != null) return report(exit);
    return ErrorReportingManager.recordError(
      AndroidProcessExitException(exit.reason),
      StackTrace.current,
      reason: AppStrings.androidProcessExitUnhandled,
      extraInfo: exit.toExtraInfo(),
    );
  }

  Future<int> _readLastReportedExitMs() async {
    final read = _deps.readLastReportedExitMs;
    if (read != null) return read();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(lastReportedExitPrefKey) ?? 0;
  }

  Future<void> _writeLastReportedExitMs(int timestampMs) async {
    final write = _deps.writeLastReportedExitMs;
    if (write != null) {
      await write(timestampMs);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(lastReportedExitPrefKey, timestampMs);
  }

  DateTime _now() => clock();

  String _appVersion() {
    final custom = _deps.appVersion;
    if (custom != null) return custom();
    return ClientIdentification.httpHeaders['X-Client-Version'] ?? 'unknown';
  }
}

int _maxTimestamp(List<AndroidProcessExit> exits) {
  var max = 0;
  for (final exit in exits) {
    if (exit.timestampMs > max) max = exit.timestampMs;
  }
  return max;
}
