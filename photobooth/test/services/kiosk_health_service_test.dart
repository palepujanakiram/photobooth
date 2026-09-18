import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/android_process_exit.dart';
import 'package:photobooth/services/error_reporting/error_reporting_manager.dart';
import 'package:photobooth/services/kiosk_health_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

AndroidProcessExit exitAt(int ts, {String reason = 'LOW_MEMORY'}) {
  return AndroidProcessExit(timestampMs: ts, reason: reason);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    KioskHealthService.sendHeartbeat = null;
    KioskHealthService.clock = DateTime.now;
    await ErrorReportingManager.initialize(enableBugsnag: false);
    await ErrorReportingManager.setEnabled(true);
  });

  tearDown(() {
    KioskHealthService.sendHeartbeat = null;
    KioskHealthService.clock = DateTime.now;
    KioskHealthService.instance.stop();
  });

  test('singleton and periodic ping', () {
    expect(KioskHealthService.instance, isA<KioskHealthService>());
    fakeAsync((async) {
      var pings = 0;
      final svc = KioskHealthService(
        heartbeatInterval: const Duration(seconds: 5),
        deps: KioskHealthServiceDeps(
          readKioskCode: () async {
            pings += 1;
            return null;
          },
        ),
      );
      svc.start();
      svc.start();
      async.flushMicrotasks();
      expect(svc.isRunning, isTrue);
      expect(pings, 1);
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      expect(pings, 2);
      svc.stop();
      expect(svc.isRunning, isFalse);
    });
  });

  test('default now and historical-exit channel when no extras', () async {
    var posted = 0;
    final svc = KioskHealthService(
      deps: KioskHealthServiceDeps(
        readKioskCode: () async => 'K1',
        postHeartbeat: (_) async {
          posted += 1;
        },
        readLastReportedExitMs: () async => 0,
        appVersion: () => 't',
      ),
    );
    await svc.ping();
    expect(posted, 1);
  });

  test('ping no-ops without a bound kiosk code', () async {
    var posted = 0;
    final svc = KioskHealthService(
      deps: KioskHealthServiceDeps(
        readKioskCode: () async => '  ',
        postHeartbeat: (_) async {
          posted += 1;
        },
      ),
    );
    await svc.ping();
    expect(posted, 0);
  });

  test('overlapping ping reuses the in-flight future', () async {
    final started = Completer<void>();
    final gate = Completer<void>();
    var bodies = 0;
    final svc = KioskHealthService(
      deps: KioskHealthServiceDeps(
        readKioskCode: () async {
          bodies += 1;
          started.complete();
          await gate.future;
          return 'K1';
        },
        readExits: () async => const [],
        postHeartbeat: (_) async {},
        readLastReportedExitMs: () async => 0,
        appVersion: () => 't',
      ),
    );
    final first = svc.ping();
    await started.future;
    final second = svc.ping();
    expect(identical(first, second), isTrue);
    gate.complete();
    await first;
    expect(bodies, 1);
  });

  test('reports unexpected exits, skips expected and already-reported', () async {
    final now = DateTime.utc(2026, 9, 9, 14);
    KioskHealthService.clock = () => now;
    final fresh = now.millisecondsSinceEpoch - 1000;
    final stale = now.millisecondsSinceEpoch - const Duration(hours: 30).inMilliseconds;
    final posted = <KioskHeartbeatRequest>[];
    final reported = <String>[];
    var stored = 0;
    final svc = KioskHealthService(
      deps: KioskHealthServiceDeps(
        readKioskCode: () async => 'dps1',
        readExits: () async => [
          exitAt(stale),
          exitAt(fresh - 10, reason: 'EXIT_SELF'),
          exitAt(fresh, reason: 'ANR'),
          exitAt(fresh + 5, reason: 'CRASH'),
        ],
        postHeartbeat: (request) async {
          posted.add(request);
        },
        reportExit: (e) async => reported.add(e.reason),
        readLastReportedExitMs: () async => fresh - 20,
        writeLastReportedExitMs: (ts) async => stored = ts,
        appVersion: () => '2026.9.9',
      ),
    );
    await svc.ping();
    expect(reported, ['ANR', 'CRASH']);
    expect(posted, hasLength(1));
    expect(posted.single.kioskCode, 'DPS1');
    expect(posted.single.appVersion, '2026.9.9');
    expect(posted.single.processExits.map((e) => e.reason), ['ANR', 'CRASH']);
    expect(stored, fresh + 5);
  });

  test('does not persist last-exit watermark when heartbeat is missing', () async {
    var stored = 0;
    final now = DateTime.utc(2026, 9, 9, 12);
    KioskHealthService.clock = () => now;
    final svc = KioskHealthService(
      deps: KioskHealthServiceDeps(
        readKioskCode: () async => 'K1',
        readExits: () async => [exitAt(now.millisecondsSinceEpoch)],
        reportExit: (_) async {},
        readLastReportedExitMs: () async => 0,
        writeLastReportedExitMs: (ts) async => stored = ts,
      ),
    );
    await svc.ping();
    expect(stored, 0);
  });

  test('logs warning when heartbeat throws and skips watermark', () async {
    var stored = 0;
    final now = DateTime.utc(2026, 9, 9, 12);
    KioskHealthService.clock = () => now;
    final svc = KioskHealthService(
      deps: KioskHealthServiceDeps(
        readKioskCode: () async => 'K1',
        readExits: () async => [exitAt(now.millisecondsSinceEpoch)],
        postHeartbeat: (_) async => throw StateError('offline'),
        reportExit: (_) async {},
        readLastReportedExitMs: () async => 0,
        writeLastReportedExitMs: (ts) async => stored = ts,
        appVersion: () => 't',
      ),
    );
    await svc.ping();
    expect(stored, 0);
  });

  test('uses static sendHeartbeat and default prefs / reporter / version', () async {
    SharedPreferences.setMockInitialValues({'kiosk_code': 'k2'});
    final posted = <KioskHeartbeatRequest>[];
    KioskHealthService.sendHeartbeat = (request) async {
      posted.add(request);
    };
    final now = DateTime.utc(2026, 9, 9, 13);
    KioskHealthService.clock = () => now;
    final svc = KioskHealthService(
      deps: KioskHealthServiceDeps(
        readExits: () async => [exitAt(now.millisecondsSinceEpoch, reason: 'LOW_MEMORY')],
      ),
    );
    await svc.ping();
    expect(posted, hasLength(1));
    expect(posted.single.kioskCode, 'K2');
    expect(posted.single.appVersion, 'unknown');
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getInt(KioskHealthService.lastReportedExitPrefKey),
      now.millisecondsSinceEpoch,
    );
  });

  test('cutoff uses history window when last-reported is older', () async {
    final now = DateTime.utc(2026, 9, 9, 12);
    KioskHealthService.clock = () => now;
    final insideWindow = now.millisecondsSinceEpoch - const Duration(hours: 1).inMilliseconds;
    final posted = <KioskHeartbeatRequest>[];
    final svc = KioskHealthService(
      historyWindow: const Duration(hours: 24),
      deps: KioskHealthServiceDeps(
        readKioskCode: () async => 'K1',
        readExits: () async => [exitAt(insideWindow)],
        postHeartbeat: (request) async {
          posted.add(request);
        },
        reportExit: (_) async {},
        readLastReportedExitMs: () async => 1,
        writeLastReportedExitMs: (_) async {},
        appVersion: () => 't',
      ),
    );
    await svc.ping();
    expect(posted.single.processExits, hasLength(1));
  });
}
