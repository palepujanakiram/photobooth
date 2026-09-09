import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_pipeline/event_frame.dart';
import 'package:photobooth/models/event_pipeline/event_pipeline_settings.dart';
import 'package:photobooth/models/event_pipeline/event_readiness.dart';
import 'package:photobooth/models/event_pipeline/printer_consumables.dart';

const int gb = 1024 * 1024 * 1024;

EventPipelineSettings settings({
  bool aiEnabled = false,
  String? themeId,
  bool frameEnabled = false,
  String? frameId,
  String printSize = 's4x6',
}) {
  return EventPipelineSettings(
    pipelineEnabled: true,
    offlineMode: false,
    aiEnabled: aiEnabled,
    themeId: themeId,
    frameEnabled: frameEnabled,
    frameId: frameId,
    autoPrint: true,
    defaultCopies: 1,
    printSize: printSize,
    qualityFactor: 1.0,
    mirrorEnabled: false,
    scanFolders: const ['DCIM'],
  );
}

/// A device where nothing is wrong, so each test can break exactly one thing.
EventReadinessInput healthy({
  EventPipelineSettings? config,
  bool hasSyncedOnce = true,
  bool syncIsFresh = true,
  int? syncedAtMs = 1700000000000,
  String? syncError,
  String? cameraName = 'Canon EOS R',
  PrinterConsumables? printer = const PrinterConsumables(
    code: 0,
    readiness: PrinterReadiness.ready,
    name: 'DS-RX1',
  ),
  FrameCacheStatus? frames,
  int? freeBytes = 46 * gb,
  bool online = true,
}) {
  return EventReadinessInput(
    settings: config ?? settings(),
    hasSyncedOnce: hasSyncedOnce,
    syncIsFresh: syncIsFresh,
    syncedAtMs: syncedAtMs,
    syncError: syncError,
    cameraName: cameraName,
    printer: printer,
    frames: frames,
    freeBytes: freeBytes,
    online: online,
  );
}

ReadinessRow rowOf(EventReadinessReport report, ReadinessKind kind) =>
    report.rows.firstWhere((r) => r.kind == kind);

void main() {
  group('a healthy device', () {
    test('is ready to run with every row green', () {
      final report = EventReadiness.evaluate(healthy());
      expect(report.isReady, isTrue);
      expect(report.headline, 'READY TO RUN');
      expect(report.canImport, isTrue);
      expect(report.canCapture, isTrue);
      expect(report.importBlockedReason, isNull);
      expect(report.captureBlockedReason, isNull);
    });

    test('has one row per thing that can quietly not be ready', () {
      final report = EventReadiness.evaluate(healthy());
      expect(
        report.rows.map((r) => r.kind).toList(),
        ReadinessKind.values,
      );
    });

    test('green rows are not tappable', () {
      final report = EventReadiness.evaluate(healthy());
      expect(report.rows.every((r) => !r.isActionable), isTrue);
    });
  });

  group('settings row', () {
    test('never synced blocks import and says why on the button', () {
      final report =
          EventReadiness.evaluate(healthy(hasSyncedOnce: false));

      final row = rowOf(report, ReadinessKind.sync);
      expect(row.tone, ReadinessTone.blocked);
      expect(row.isActionable, isTrue);
      expect(report.canImport, isFalse);
      expect(report.canCapture, isFalse);
      expect(report.importBlockedReason, EventReadiness.waitingForSettings);
      expect(report.headline, 'NOT READY');
    });

    test('a fetch failure carries its own reason onto the row', () {
      final report = EventReadiness.evaluate(healthy(
        hasSyncedOnce: false,
        syncError: 'Could not reach ZenAI',
      ));
      expect(rowOf(report, ReadinessKind.sync).explanation,
          'Could not reach ZenAI');
    });

    test('a fresh sync shows the clock time', () {
      final at = DateTime(2026, 9, 9, 9, 12).millisecondsSinceEpoch;
      final report = EventReadiness.evaluate(healthy(syncedAtMs: at));
      expect(rowOf(report, ReadinessKind.sync).detail, 'Synced 09:12');
    });

    test('running on cache is amber and names the day, not the minute', () {
      final at = DateTime(2026, 9, 8, 17, 4).millisecondsSinceEpoch;
      final report = EventReadiness.evaluate(
        healthy(syncIsFresh: false, syncedAtMs: at),
      );

      final row = rowOf(report, ReadinessKind.sync);
      expect(row.tone, ReadinessTone.warn);
      expect(row.detail, 'Using settings from 8 Sep');
      expect(report.canImport, isTrue,
          reason: 'a cached event has a chain to freeze, so it runs');
    });
  });

  group('camera row', () {
    test('no camera disables Capture but not Import', () {
      final report = EventReadiness.evaluate(healthy(cameraName: null));

      expect(rowOf(report, ReadinessKind.camera).tone, ReadinessTone.blocked);
      expect(report.canCapture, isFalse);
      expect(report.captureBlockedReason, 'No camera connected');
      expect(report.canImport, isTrue,
          reason: 'cards do not need a camera');
    });

    test('a blank name reads as not connected', () {
      final report = EventReadiness.evaluate(healthy(cameraName: '   '));
      expect(rowOf(report, ReadinessKind.camera).tone, ReadinessTone.blocked);
    });

    test('a connected camera is named', () {
      final report = EventReadiness.evaluate(healthy());
      expect(rowOf(report, ReadinessKind.camera).detail, 'Canon EOS R');
    });
  });

  group('printer row', () {
    test('no printer is red and explains that prints still queue', () {
      final report = EventReadiness.evaluate(
        healthy(printer: PrinterConsumables.offline),
      );
      final row = rowOf(report, ReadinessKind.printer);
      expect(row.tone, ReadinessTone.blocked);
      expect(row.explanation, contains('queue up'));
    });

    test('an unread printer is treated as absent rather than assumed ready',
        () {
      final report = EventReadiness.evaluate(healthy(printer: null));
      expect(rowOf(report, ReadinessKind.printer).tone, ReadinessTone.blocked);
    });

    test('needing attention shows the real reason, not a category', () {
      final report = EventReadiness.evaluate(healthy(
        printer: const PrinterConsumables(
          code: 1200,
          readiness: PrinterReadiness.needsAttention,
          label: 'Ribbon end — replace ribbon',
        ),
      ));
      final row = rowOf(report, ReadinessKind.printer);
      expect(row.tone, ReadinessTone.blocked);
      expect(row.detail, 'Ribbon end — replace ribbon');
    });

    test('a ready printer names itself and the loaded size', () {
      final report =
          EventReadiness.evaluate(healthy(config: settings(printSize: 's6x8')));
      expect(rowOf(report, ReadinessKind.printer).detail, 'DS-RX1 · s6x8');
    });

    test('a printer that will not print does not block import', () {
      final report = EventReadiness.evaluate(
        healthy(printer: PrinterConsumables.offline),
      );
      expect(report.canImport, isTrue);
    });
  });

  group('frames row', () {
    test('framing off is green and says so', () {
      final report = EventReadiness.evaluate(healthy());
      final row = rowOf(report, ReadinessKind.frames);
      expect(row.tone, ReadinessTone.ok);
      expect(row.detail, 'off for this event');
    });

    test('framing on with the artwork missing is red', () {
      // The row that most needs the explanation: silent until the event goes
      // offline, and then every single item defers.
      final report = EventReadiness.evaluate(healthy(
        config: settings(frameEnabled: true, frameId: 'f1'),
        frames: const FrameCacheStatus(
          total: 3,
          cached: 2,
          selectedIsCached: false,
        ),
      ));
      final row = rowOf(report, ReadinessKind.frames);
      expect(row.tone, ReadinessTone.blocked);
      expect(row.detail, 'Event frame missing');
      expect(row.explanation, contains('while there is still signal'));
    });

    test('no frames cached at all reads differently from the wrong one', () {
      final report = EventReadiness.evaluate(healthy(
        config: settings(frameEnabled: true, frameId: 'f1'),
        frames: const FrameCacheStatus(
          total: 0,
          cached: 0,
          selectedIsCached: false,
        ),
      ));
      expect(rowOf(report, ReadinessKind.frames).detail, 'None cached');
    });

    test('the event frame present but others missing is amber, not red', () {
      final report = EventReadiness.evaluate(healthy(
        config: settings(frameEnabled: true, frameId: 'f1'),
        frames: const FrameCacheStatus(
          total: 3,
          cached: 1,
          selectedIsCached: true,
        ),
      ));
      final row = rowOf(report, ReadinessKind.frames);
      expect(row.tone, ReadinessTone.warn);
      expect(row.detail, '1 of 3 cached');
    });

    test('all cached is green', () {
      final report = EventReadiness.evaluate(healthy(
        config: settings(frameEnabled: true, frameId: 'f1'),
        frames: const FrameCacheStatus(
          total: 2,
          cached: 2,
          selectedIsCached: true,
        ),
      ));
      final row = rowOf(report, ReadinessKind.frames);
      expect(row.tone, ReadinessTone.ok);
      expect(row.detail, '2 cached');
    });

    test('unchecked frames are amber rather than assumed fine', () {
      final report = EventReadiness.evaluate(healthy(
        config: settings(frameEnabled: true, frameId: 'f1'),
        frames: null,
      ));
      expect(rowOf(report, ReadinessKind.frames).tone, ReadinessTone.warn);
    });

    test('a missing frame does not block import — it blocks framing', () {
      final report = EventReadiness.evaluate(healthy(
        config: settings(frameEnabled: true, frameId: 'f1'),
        frames: const FrameCacheStatus(
          total: 1,
          cached: 0,
          selectedIsCached: false,
        ),
      ));
      expect(report.canImport, isTrue);
      expect(report.headline, 'NOT READY');
    });
  });

  group('AI row', () {
    test('AI off is green', () {
      expect(
        rowOf(EventReadiness.evaluate(healthy()), ReadinessKind.ai).tone,
        ReadinessTone.ok,
      );
    });

    test('AI on with no theme is amber — the step is skipped, not stuck', () {
      final report = EventReadiness.evaluate(
        healthy(config: settings(aiEnabled: true)),
      );
      final row = rowOf(report, ReadinessKind.ai);
      expect(row.tone, ReadinessTone.warn);
      expect(row.detail, 'No theme set');
      expect(row.explanation, contains('skipped'));
    });

    test('AI on and offline is red, with jobs waiting rather than failing', () {
      final report = EventReadiness.evaluate(healthy(
        config: settings(aiEnabled: true, themeId: 'theme-a'),
        online: false,
      ));
      final row = rowOf(report, ReadinessKind.ai);
      expect(row.tone, ReadinessTone.blocked);
      expect(row.detail, 'Offline · theme theme-a');
      expect(row.explanation, contains('nothing is lost'));
    });

    test('AI on, themed and online is green and names the theme', () {
      final report = EventReadiness.evaluate(
        healthy(config: settings(aiEnabled: true, themeId: 'theme-a')),
      );
      final row = rowOf(report, ReadinessKind.ai);
      expect(row.tone, ReadinessTone.ok);
      expect(row.detail, 'on · theme theme-a');
    });

    test('being offline never blocks import', () {
      final report = EventReadiness.evaluate(healthy(
        config: settings(aiEnabled: true, themeId: 'theme-a'),
        online: false,
      ));
      expect(report.canImport, isTrue);
    });
  });

  group('storage row', () {
    test('plenty of space is green', () {
      final report = EventReadiness.evaluate(healthy());
      final row = rowOf(report, ReadinessKind.storage);
      expect(row.tone, ReadinessTone.ok);
      expect(row.detail, '46 GB free');
    });

    test('below 4 GB is amber but still importable', () {
      final report = EventReadiness.evaluate(healthy(freeBytes: 3 * gb));
      expect(rowOf(report, ReadinessKind.storage).tone, ReadinessTone.warn);
      expect(report.canImport, isTrue);
    });

    test('below 1 GB blocks import with its reason on the button', () {
      final report = EventReadiness.evaluate(
        healthy(freeBytes: 512 * 1024 * 1024),
      );
      expect(rowOf(report, ReadinessKind.storage).tone, ReadinessTone.blocked);
      expect(report.canImport, isFalse);
      expect(report.importBlockedReason, 'Not enough free space');
      expect(report.canCapture, isFalse);
    });

    test('sub-gigabyte space is reported in MB', () {
      final report = EventReadiness.evaluate(
        healthy(freeBytes: 512 * 1024 * 1024),
      );
      expect(rowOf(report, ReadinessKind.storage).detail, '512 MB free');
    });

    test('unreadable free space is amber, not silently fine', () {
      final report = EventReadiness.evaluate(healthy(freeBytes: null));
      expect(rowOf(report, ReadinessKind.storage).tone, ReadinessTone.warn);
      expect(report.canImport, isTrue,
          reason: 'an unreadable disk is not proof it is full');
    });
  });

  group('gating precedence', () {
    test('an unsynced event names the sync, not the disk', () {
      // Both are wrong; the operator can fix the sync in seconds and the disk
      // not at all, so the sync is the reason worth printing.
      final report = EventReadiness.evaluate(
        healthy(hasSyncedOnce: false, freeBytes: 100),
      );
      expect(report.importBlockedReason, EventReadiness.waitingForSettings);
    });

    test('warnings alone are still runnable, and say so', () {
      final report = EventReadiness.evaluate(healthy(freeBytes: 3 * gb));
      expect(report.headline, 'READY — WITH WARNINGS');
      expect(report.hasBlocker, isFalse);
      expect(report.isReady, isFalse);
    });
  });

  group('formatBytes', () {
    test('rounds to whole GB above a gigabyte', () {
      expect(EventReadiness.formatBytes(46 * gb), '46 GB');
      expect(EventReadiness.formatBytes(gb), '1 GB');
    });

    test('falls back to MB below a gigabyte', () {
      expect(EventReadiness.formatBytes(200 * 1024 * 1024), '200 MB');
      expect(EventReadiness.formatBytes(0), '0 MB');
    });
  });

  group('timestamps with nothing recorded', () {
    test('a fresh sync with no stamp still reads sensibly', () {
      final report =
          EventReadiness.evaluate(healthy(syncedAtMs: null));
      expect(rowOf(report, ReadinessKind.sync).detail, 'Synced just now');
    });

    test('a cached sync with no stamp does not invent a date', () {
      final report = EventReadiness.evaluate(
        healthy(syncIsFresh: false, syncedAtMs: null),
      );
      expect(
        rowOf(report, ReadinessKind.sync).detail,
        'Using settings from an earlier session',
      );
    });
  });
}
