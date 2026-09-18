import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_pipeline/event_pipeline_flags.dart';
import 'package:photobooth/models/event_pipeline/event_pipeline_settings.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EventPipelineConfig config;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    EventPipelineConfig.resetCacheForTests();
    config = EventPipelineConfig();
  });

  group('cached backend flags', () {
    test('cache and read back', () async {
      await config.cacheFlags(
        const EventPipelineFlags(pipelineEnabled: true, themeId: 'theme-x'),
      );
      final back = await config.readCachedFlags();
      expect(back.pipelineEnabled, isTrue);
      expect(back.themeId, 'theme-x');
    });

    test('caching empty flags clears the entry', () async {
      await config.cacheFlags(const EventPipelineFlags(pipelineEnabled: true));
      await config.cacheFlags(EventPipelineFlags.empty);
      expect((await config.readCachedFlags()).isEmpty, isTrue);
    });

    test('a corrupt cache inherits defaults instead of throwing', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('evp_cached_flags_json', 'not json{');
      expect((await config.readCachedFlags()).isEmpty, isTrue);
    });

    test('clearCachedFlags drops the auto-print override too', () async {
      await config.setAutoPrintOverride(true);
      await config.clearCachedFlags();
      expect(await config.readAutoPrintOverride(), isNull);
    });

    test('clearCachedFlags empties the cache', () async {
      await config.cacheFlags(const EventPipelineFlags(aiEnabled: true));
      await config.clearCachedFlags();
      expect((await config.readCachedFlags()).isEmpty, isTrue);
    });

    test('clearCachedFlags drops the sync pipeline-enabled snapshot too',
        () async {
      await config.resolve(
        flags: const EventPipelineFlags(pipelineEnabled: true),
      );
      expect(EventPipelineConfig.isPipelineEnabledCached, isTrue);
      await config.clearCachedFlags();
      expect(EventPipelineConfig.isPipelineEnabledCached, isFalse);
    });
  });

  group('sync record', () {
    test('records and reads back the time this event synced', () async {
      expect(await config.hasSyncedOnce('GALA-01'), isFalse);
      await config.recordSyncedAt('GALA-01', 1700000000000);
      expect(await config.readSyncedAtMs('GALA-01'), 1700000000000);
      expect(await config.hasSyncedOnce('GALA-01'), isTrue);
    });

    test('the code is matched case- and space-insensitively', () async {
      await config.recordSyncedAt('  gala-01 ', 42);
      expect(await config.readSyncedAtMs('GALA-01'), 42);
    });

    test('a different event reads as never synced', () async {
      await config.recordSyncedAt('GALA-01', 42);
      expect(await config.readSyncedAtMs('WEDDING-02'), isNull,
          reason: 'last weekend\'s sync must not unblock this weekend');
    });

    test('binding a different event drops the auto-print override', () async {
      await config.recordSyncedAt('GALA-01', 42);
      await config.setAutoPrintOverride(true);
      await config.recordSyncedAt('WEDDING-02', 43);
      expect(await config.readAutoPrintOverride(), isNull,
          reason: 'last weekend\'s "auto print on" must not print this one');
    });

    test('re-syncing the same event keeps the auto-print override', () async {
      await config.recordSyncedAt('GALA-01', 42);
      await config.setAutoPrintOverride(true);
      await config.recordSyncedAt('  gala-01  ', 43);
      expect(await config.readAutoPrintOverride(), isTrue);
    });

    test('the first sync keeps an override set before it', () async {
      await config.setAutoPrintOverride(true);
      await config.recordSyncedAt('GALA-01', 42);
      expect(await config.readAutoPrintOverride(), isTrue);
    });

    test('a blank code is not a syncable event', () async {
      await config.recordSyncedAt('   ', 42);
      expect(await config.readSyncedAtMs(''), isNull);
    });

    test('the stamp survives caching flags separately', () async {
      await config.recordSyncedAt('GALA-01', 42);
      // A backend that sends no pipeline fields still synced; the event then
      // runs on defaults rather than being blocked forever.
      await config.cacheFlags(EventPipelineFlags.empty);
      expect(await config.hasSyncedOnce('GALA-01'), isTrue);
      expect((await config.readCachedFlags()).isEmpty, isTrue);
    });

    test('clearCachedFlags clears the stamp too', () async {
      await config.recordSyncedAt('GALA-01', 42);
      await config.clearCachedFlags();
      expect(await config.hasSyncedOnce('GALA-01'), isFalse);
    });
  });

  group('resolve', () {
    test('defaults apply when nothing is configured', () async {
      final s = await config.resolve();
      expect(s.pipelineEnabled, isFalse);
      expect(s.offlineMode, isFalse);
      expect(s.aiEnabled, isTrue); // photoMode BOTH
      expect(s.frameEnabled, isFalse); // frameCount 0
      expect(s.defaultCopies, 1);
      expect(s.printSize, 's4x6');
      expect(s.qualityFactor, 1.0);
      expect(s.mirrorEnabled, isTrue);
      expect(s.scanFolders, ['DCIM']);
    });

    test('event defaults drive AI and framing', () async {
      final s = await config.resolve(
        defaults: const EventPipelineDefaults(
          photoMode: 'FRAME_ONLY',
          frameCount: 3,
          printSize: 's6x8',
        ),
      );
      expect(s.aiEnabled, isFalse);
      expect(s.frameEnabled, isTrue);
      expect(s.printSize, 's6x8');
    });

    test('backend flags beat defaults', () async {
      final s = await config.resolve(
        flags: const EventPipelineFlags(
          pipelineEnabled: true,
          aiEnabled: false,
          defaultCopies: 2,
        ),
      );
      expect(s.pipelineEnabled, isTrue);
      expect(s.aiEnabled, isFalse);
      expect(s.defaultCopies, 2);
    });

    test('a backend false is honoured, not treated as unset', () async {
      final s = await config.resolve(
        flags: const EventPipelineFlags(aiEnabled: false),
        defaults: const EventPipelineDefaults(photoMode: 'BOTH'),
      );
      expect(s.aiEnabled, isFalse);
    });

    test('passed flags win over the cache rather than merging with it',
        () async {
      await config.cacheFlags(
        const EventPipelineFlags(pipelineEnabled: true, themeId: 'stale'),
      );
      final s = await config.resolve(
        flags: const EventPipelineFlags(pipelineEnabled: true),
      );
      expect(s.themeId, isNull);
    });

    test('falls back to cached flags when none are passed', () async {
      await config.cacheFlags(
        const EventPipelineFlags(pipelineEnabled: true, themeId: 'cached'),
      );
      final s = await config.resolve();
      expect(s.pipelineEnabled, isTrue);
      expect(s.themeId, 'cached');
    });

    test('offline mode forces mirroring off despite the backend flag',
        () async {
      final s = await config.resolve(
        flags: const EventPipelineFlags(
          offlineMode: true,
          mirrorEnabled: true,
        ),
      );
      expect(s.offlineMode, isTrue);
      expect(s.mirrorEnabled, isFalse);
    });

    test('offline mode does not force AI off — those jobs wait instead',
        () async {
      final s = await config.resolve(
        flags: const EventPipelineFlags(offlineMode: true, aiEnabled: true),
      );
      expect(s.aiEnabled, isTrue);
    });

    test('autoPrint inherits printerEnabled when nothing else says', () async {
      final off = await config.resolve(
        defaults: const EventPipelineDefaults(printerEnabled: false),
      );
      expect(off.autoPrint, isFalse);
      final on = await config.resolve(
        defaults: const EventPipelineDefaults(printerEnabled: true),
      );
      expect(on.autoPrint, isTrue);
    });

    test('a local override beats an explicit backend autoPrint', () async {
      // The case that matters in the field: ZenAI sends `false` for every event
      // because its admin UI cannot set the column, so without the override
      // there is no way to reach an auto-printing chain at all.
      await config.setAutoPrintOverride(true);
      final s = await config.resolve(
        flags: const EventPipelineFlags(autoPrint: false),
      );
      expect(s.autoPrint, isTrue);
    });

    test('a local override can also turn autoPrint off', () async {
      await config.setAutoPrintOverride(false);
      final s = await config.resolve(
        flags: const EventPipelineFlags(autoPrint: true),
      );
      expect(s.autoPrint, isFalse);
    });

    test('clearing the override defers to the backend again', () async {
      await config.setAutoPrintOverride(true);
      await config.setAutoPrintOverride(null);
      expect(await config.readAutoPrintOverride(), isNull);
      final s = await config.resolve(
        flags: const EventPipelineFlags(autoPrint: false),
      );
      expect(s.autoPrint, isFalse);
    });

    test('with no override and no backend opinion, printerEnabled still wins',
        () async {
      expect(await config.readAutoPrintOverride(), isNull);
      final s = await config.resolve(
        defaults: const EventPipelineDefaults(printerEnabled: false),
      );
      expect(s.autoPrint, isFalse);
    });

    test('resolve populates the sync pipeline-enabled snapshot', () async {
      expect(EventPipelineConfig.isPipelineEnabledCached, isFalse);
      await config.resolve(
        flags: const EventPipelineFlags(pipelineEnabled: true),
      );
      expect(EventPipelineConfig.isPipelineEnabledCached, isTrue);
    });

    test('resolved settings produce the expected frozen chain', () async {
      final s = await config.resolve(
        flags: const EventPipelineFlags(
          pipelineEnabled: true,
          aiEnabled: true,
          themeId: 't1',
          frameEnabled: true,
          frameId: 'f1',
          autoPrint: true,
        ),
      );
      expect(s.resolveSteps(), ['ai', 'frame', 'print']);
    });
  });
}
