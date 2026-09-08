import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_pipeline/media_item.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_config.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_db.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_stats.dart';
import 'package:photobooth/utils/event_station_role.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late EventPipelineDb db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    EventPipelineConfig.resetCacheForTests();
    EventPipelineStatsReader.resetSharedForTests();
    root = await Directory.systemTemp.createTemp('fz_evp_impact_');
    db = (await EventPipelineDb.open(root))!;
  });

  tearDown(() async {
    EventPipelineStatsReader.resetSharedForTests();
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('guest kiosk routing is untouched', () {
    test('a kiosk with no event code always goes to Terms', () {
      for (final wan in [true, false]) {
        for (final pipeline in [true, false]) {
          expect(
            resolveEventPostSplashRoute(
              eventCode: null,
              stationRole: null,
              wanAvailable: wan,
              pipelineEnabled: pipeline,
            ),
            EventPostSplashRoute.terms,
            reason: 'wan=$wan pipeline=$pipeline must not change a guest kiosk',
          );
        }
      }
    });

    test('an event device with no station role still goes to the picker', () {
      expect(
        resolveEventPostSplashRoute(
          eventCode: 'GALA',
          stationRole: null,
          wanAvailable: false,
        ),
        EventPostSplashRoute.stationPicker,
      );
    });

    test('the pipeline-off default reproduces the previous behaviour exactly',
        () {
      // Every combination that existed before the flag was added.
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
          stationRole: 'theme',
          wanAvailable: true,
        ),
        EventPostSplashRoute.theme,
      );
      expect(
        resolveEventPostSplashRoute(
          eventCode: 'GALA',
          stationRole: 'print',
          wanAvailable: true,
        ),
        EventPostSplashRoute.print,
      );
    });

    test('an unknown role parses to null and does not gate on WAN', () {
      expect(
        stationRequiresWan(stationRole: 'nonsense', pipelineEnabled: false),
        isFalse,
      );
    });
  });

  group('stats reader opens the database once', () {
    test('repeated reads reuse one handle', () async {
      var opens = 0;
      final reader = EventPipelineStatsReader(openDb: () async {
        opens++;
        return db;
      });
      for (var i = 0; i < 5; i++) {
        await reader.read();
      }
      // Polled on a timer by every station; reopening per tick would re-run the
      // schema DDL every few seconds and leak a connection each time.
      expect(opens, 1);
    });

    test('concurrent reads do not race into a second open', () async {
      var opens = 0;
      final reader = EventPipelineStatsReader(openDb: () async {
        opens++;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return db;
      });
      await Future.wait([reader.read(), reader.read(), reader.read()]);
      expect(opens, 1);
    });
  });
}
