import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_pipeline/media_item.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_db.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_ledger.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_queue.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_stats.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/utils/event_station_role.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // The stats reader looks up the bound event to scope its counts, which needs
  // the platform binding and a prefs store.
  TestWidgetsFlutterBinding.ensureInitialized();
  group('stationRequiresWan', () {
    test('every station needs WAN with the pipeline off', () {
      for (final role in EventStationRole.values) {
        expect(
          stationRequiresWan(stationRole: role, pipelineEnabled: false),
          isTrue,
          reason: '$role is server-brokered without the pipeline',
        );
      }
    });

    test('no station needs WAN with the pipeline on', () {
      for (final role in EventStationRole.values) {
        expect(
          stationRequiresWan(stationRole: role, pipelineEnabled: true),
          isFalse,
        );
      }
    });

    test('a guest device with no role never needs WAN for this reason', () {
      expect(
        stationRequiresWan(stationRole: null, pipelineEnabled: false),
        isFalse,
      );
    });
  });

  group('resolveEventPostSplashRoute', () {
    test('regression: the pipeline-off path is unchanged', () {
      // The default must match the behaviour from before the pipeline existed.
      expect(
        resolveEventPostSplashRoute(
          eventCode: 'GALA',
          stationRole: 'capture',
          wanAvailable: false,
        ),
        EventPostSplashRoute.needsInternet,
      );
      expect(
        resolveEventPostSplashRoute(
          eventCode: 'GALA',
          stationRole: 'capture',
        ),
        EventPostSplashRoute.capture,
      );
    });

    test('an offline event boots straight to its station', () {
      for (final role in EventStationRole.values) {
        final dest = resolveEventPostSplashRoute(
          eventCode: 'GALA',
          stationRole: role,
          wanAvailable: false,
          pipelineEnabled: true,
        );
        expect(
          dest,
          isNot(EventPostSplashRoute.needsInternet),
          reason: '$role must boot offline when the pipeline is on',
        );
      }
    });

    test('an unknown role still lands on the station picker', () {
      expect(
        resolveEventPostSplashRoute(
          eventCode: 'GALA',
          stationRole: 'sd-import',
        ),
        EventPostSplashRoute.stationPicker,
      );
    });

    test('the pipeline replaces the picker with the hub', () {
      expect(
        resolveEventPostSplashRoute(
          eventCode: 'GALA',
          stationRole: null,
          pipelineEnabled: true,
        ),
        EventPostSplashRoute.hub,
      );
      expect(
        eventPostSplashRouteName(EventPostSplashRoute.hub),
        AppConstants.kRouteEventHub,
      );
    });

    test('a station role does not escape the hub when the flag is on', () {
      // There is no role to pick any more: three sources feed one queue on one
      // device, so a leftover role from a previous event must not route past
      // the hub.
      for (final role in EventStationRole.values) {
        expect(
          resolveEventPostSplashRoute(
            eventCode: 'GALA',
            stationRole: role,
            pipelineEnabled: true,
          ),
          EventPostSplashRoute.hub,
          reason: '$role',
        );
      }
    });

    test('an offline event still reaches the hub', () {
      expect(
        resolveEventPostSplashRoute(
          eventCode: 'GALA',
          stationRole: 'capture',
          wanAvailable: false,
          pipelineEnabled: true,
        ),
        EventPostSplashRoute.hub,
      );
    });

    test('regression: every flag-off destination is unchanged', () {
      // The guard on the whole phase. With the flag off, routing must be
      // byte-identical to the behaviour from before the pipeline existed.
      expect(
        resolveEventPostSplashRoute(eventCode: null, stationRole: 'capture'),
        EventPostSplashRoute.terms,
      );
      expect(
        resolveEventPostSplashRoute(eventCode: '   ', stationRole: 'capture'),
        EventPostSplashRoute.terms,
      );
      expect(
        resolveEventPostSplashRoute(eventCode: 'GALA', stationRole: null),
        EventPostSplashRoute.stationPicker,
      );
      expect(
        resolveEventPostSplashRoute(eventCode: 'GALA', stationRole: 'capture'),
        EventPostSplashRoute.capture,
      );
      expect(
        resolveEventPostSplashRoute(eventCode: 'GALA', stationRole: 'theme'),
        EventPostSplashRoute.theme,
      );
      expect(
        resolveEventPostSplashRoute(eventCode: 'GALA', stationRole: 'print'),
        EventPostSplashRoute.print,
      );
      expect(
        resolveEventPostSplashRoute(
          eventCode: 'GALA',
          stationRole: 'print',
          wanAvailable: false,
        ),
        EventPostSplashRoute.needsInternet,
      );
      expect(
        resolveEventPostSplashRoute(
          eventCode: 'GALA',
          stationRole: null,
          wanAvailable: false,
        ),
        EventPostSplashRoute.stationPicker,
        reason: 'a guest device with no role never needed WAN for this',
      );
    });

    test('no event code still means guest terms', () {
      expect(
        resolveEventPostSplashRoute(
          eventCode: null,
          stationRole: 'capture',
          pipelineEnabled: true,
        ),
        EventPostSplashRoute.terms,
      );
    });
  });

  group('EventPipelineStats', () {
    test('summarises only the stages that have items', () {
      const stats = EventPipelineStats(imported: 1511, queued: 412, done: 1045);
      expect(stats.summary, 'Imported 1,511 · Queued 412 · Done 1,045');
    });

    test('an event with AI off carries no permanent "AI 0"', () {
      const stats = EventPipelineStats(imported: 5, done: 5);
      expect(stats.summary.contains('AI'), isFalse);
    });

    test('an empty ledger says so rather than showing zeroes', () {
      const stats = EventPipelineStats();
      expect(stats.isEmpty, isTrue);
      expect(stats.summary, 'Nothing imported yet');
    });

    test('thousands separators are applied', () {
      const stats = EventPipelineStats(done: 1234567);
      expect(stats.summary, 'Done 1,234,567');
    });

    test('in-flight excludes imported and terminal states', () {
      const stats = EventPipelineStats(
        imported: 10,
        queued: 1,
        ai: 2,
        framing: 3,
        printing: 4,
        done: 5,
        failed: 6,
      );
      expect(stats.inFlight, 10);
      expect(stats.total, 31);
    });
  });

  group('EventPipelineStatsReader', () {
    late Directory root;
    late EventPipelineDb db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      // The reader shares one handle process-wide, so it must be reset between
      // tests or a previous test's database leaks into this one.
      EventPipelineStatsReader.resetSharedForTests();
      root = await Directory.systemTemp.createTemp('fz_evp_stats_');
      db = (await EventPipelineDb.open(root))!;
    });

    tearDown(() async {
      EventPipelineStatsReader.resetSharedForTests();
      await db.close();
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('reads live stage counts from the ledger', () async {
      final ledger = EventPipelineLedger(db: db);
      var n = 0;
      Future<String> add() async {
        final r = await ledger.insertIfNew(
          source: MediaSource.sdCard,
          sourceRef: 'V:$n',
          contentKey: 'ck$n',
        );
        n++;
        return r.item.id;
      }

      final a = await add();
      await add();
      await ledger.markSelected(a, const ['print']);

      final stats = await EventPipelineStatsReader(openDb: () async => db).read();
      expect(stats.imported, 1);
      expect(stats.queued, 1);
      expect(stats.printPaused, isFalse);
    });

    test('reports a paused print queue', () async {
      final queue = EventPipelineQueue(db: db);
      await queue.enqueue(kind: 'print', mediaId: 'm1');
      await queue.pauseKind('print', reason: 'ribbon out');

      final stats = await EventPipelineStatsReader(openDb: () async => db).read();
      expect(stats.printPaused, isTrue);
    });

    test('no database renders an empty strip rather than throwing', () async {
      final stats = await EventPipelineStatsReader(openDb: () async => null).read();
      expect(stats.isEmpty, isTrue);
    });
  });
}
