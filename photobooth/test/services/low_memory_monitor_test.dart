import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/device_memory_snapshot.dart';
import 'package:photobooth/services/error_reporting/error_reporting_manager.dart';
import 'package:photobooth/services/low_memory_monitor.dart';

void main() {
  setUp(() async {
    await ErrorReportingManager.initialize(enableBugsnag: false);
    await ErrorReportingManager.setEnabled(true);
  });

  test('const empty snapshot covers default constructor', () {
    const snapshot = DeviceMemorySnapshot();
    expect(snapshot.processRssBytes, isNull);
    expect(snapshot.systemLowMemoryFlag, isFalse);
    final info = snapshot.toExtraInfo(trigger: 'empty');
    expect(info['process_rss_mb'], isNull);
  });

  test('non-const snapshot constructor', () {
    final snapshot = DeviceMemorySnapshot(processRssBytes: 1024);
    expect(snapshot.processRssBytes, 1024);
  });

  test('singleton instance is available', () {
    expect(LowMemoryMonitor.instance, isA<LowMemoryMonitor>());
  });

  test('detectIssueKeys reports memory pressure trigger only', () {
    final monitor = LowMemoryMonitor();
    const snapshot = DeviceMemorySnapshot(processRssBytes: 100);
    expect(
      monitor.detectIssueKeys(snapshot, trigger: 'memory_pressure'),
      ['os_memory_pressure'],
    );
  });

  test('detectIssueKeys flags system low memory and RSS on 4 GB kiosk', () {
    final monitor = LowMemoryMonitor();
    const snapshot = DeviceMemorySnapshot(
      processRssBytes: 900 * 1024 * 1024,
      availableSystemBytes: 300 * 1024 * 1024,
      totalSystemBytes: 4 * 1024 * 1024 * 1024,
      systemLowMemoryFlag: true,
    );
    final keys = monitor.detectIssueKeys(snapshot, trigger: 'poll');
    expect(keys, contains('system_low_memory_flag'));
    expect(keys, contains('system_available_below_threshold'));
    expect(keys, contains('process_rss_above_threshold'));
    expect(monitor.minAvailableBytesFor(snapshot), 400 * 1024 * 1024);
    expect(monitor.maxProcessRssFor(snapshot), 800 * 1024 * 1024);
  });

  test('detectIssueKeys uses default thresholds for sub-4 GB devices', () {
    final monitor = LowMemoryMonitor();
    const snapshot = DeviceMemorySnapshot(
      processRssBytes: 550 * 1024 * 1024,
      availableSystemBytes: 200 * 1024 * 1024,
      totalSystemBytes: 2 * 1024 * 1024 * 1024,
    );
    final keys = monitor.detectIssueKeys(snapshot, trigger: 'poll');
    expect(keys, contains('system_available_below_threshold'));
    expect(keys, contains('process_rss_above_threshold'));
    expect(monitor.minAvailableBytesFor(snapshot), 250 * 1024 * 1024);
    expect(monitor.maxProcessRssFor(snapshot), 500 * 1024 * 1024);
  });

  test('detectIssueKeys assumes 4 GB thresholds when total RAM unknown', () {
    final monitor = LowMemoryMonitor();
    const snapshot = DeviceMemorySnapshot(
      processRssBytes: 850 * 1024 * 1024,
      availableSystemBytes: 500 * 1024 * 1024,
    );
    expect(monitor.maxProcessRssFor(snapshot), 800 * 1024 * 1024);
    expect(
      monitor.detectIssueKeys(snapshot, trigger: 'poll'),
      contains('process_rss_above_threshold'),
    );
  });

  test('evaluate dedupes repeated reports within window', () async {
    var reportCount = 0;
    var now = DateTime(2026, 1, 1, 12);
    final monitor = LowMemoryMonitor(
      now: () => now,
      dedupeWindow: const Duration(minutes: 5),
      reportHandler: (_) async {
        reportCount += 1;
      },
    );
    const snapshot = DeviceMemorySnapshot(
      availableSystemBytes: 50 * 1024 * 1024,
    );

    await monitor.evaluate(snapshot, trigger: 'poll');
    await monitor.evaluate(snapshot, trigger: 'poll');
    expect(reportCount, 1);

    now = now.add(const Duration(minutes: 6));
    await monitor.evaluate(snapshot, trigger: 'poll');
    expect(reportCount, 2);
  });

  test('DeviceMemorySnapshot extraInfo formats megabytes', () {
    const snapshot = DeviceMemorySnapshot(
      processRssBytes: 2 * 1024 * 1024,
      availableSystemBytes: 3 * 1024 * 1024,
      totalSystemBytes: 4 * 1024 * 1024,
      systemLowMemoryFlag: true,
    );
    final info = snapshot.toExtraInfo(trigger: 'poll');
    expect(info['process_rss_mb'], '2.0');
    expect(info['available_system_mb'], '3.0');
    expect(info['total_system_mb'], '4.0');
    expect(info['system_low_memory_flag'], 'true');
    expect(info['trigger'], 'poll');
  });

  test('start stop and onMemoryPressure invoke evaluate', () async {
    var reports = 0;
    final monitor = LowMemoryMonitor(
      readSnapshot: () async => const DeviceMemorySnapshot(
        availableSystemBytes: 50 * 1024 * 1024,
      ),
      pollInterval: const Duration(milliseconds: 20),
      reportHandler: (_) async {
        reports += 1;
      },
    );
    monitor.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    monitor.onMemoryPressure();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    monitor.stop();
    expect(reports, greaterThanOrEqualTo(2));
  });

  test('evaluate uses ErrorReportingManager when reportHandler is null', () async {
    final monitor = LowMemoryMonitor();
    await monitor.evaluate(
      const DeviceMemorySnapshot(availableSystemBytes: 50 * 1024 * 1024),
      trigger: 'poll',
    );
  });

  test('reasonForKey default branch', () {
    final monitor = LowMemoryMonitor();
    expect(monitor.reasonForKey('unknown'), 'Device memory low');
  });

  test('_poll swallows readSnapshot errors', () async {
    final monitor = LowMemoryMonitor(
      readSnapshot: () async => throw Exception('read failed'),
      pollInterval: const Duration(hours: 1),
    );
    monitor.start();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    monitor.stop();
  });
}
