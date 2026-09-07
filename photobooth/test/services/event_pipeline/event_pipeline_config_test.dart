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

  group('overrides', () {
    test('bool overrides round-trip and clear back to inherit', () async {
      expect(await config.getPipelineEnabledOverride(), isNull);
      await config.setPipelineEnabledOverride(true);
      expect(await config.getPipelineEnabledOverride(), isTrue);
      await config.setPipelineEnabledOverride(false);
      expect(await config.getPipelineEnabledOverride(), isFalse);
      await config.setPipelineEnabledOverride(null);
      expect(await config.getPipelineEnabledOverride(), isNull);
    });

    test('string overrides treat blank as cleared', () async {
      await config.setThemeIdOverride('  theme-7 ');
      expect(await config.getThemeIdOverride(), 'theme-7');
      await config.setThemeIdOverride('   ');
      expect(await config.getThemeIdOverride(), isNull);
    });

    test('copies below 1 are refused rather than stored', () async {
      await config.setDefaultCopiesOverride(3);
      expect(await config.getDefaultCopiesOverride(), 3);
      await config.setDefaultCopiesOverride(0);
      expect(await config.getDefaultCopiesOverride(), isNull);
    });

    test('quality factor clamps to the printable range', () async {
      await config.setQualityFactorOverride(0.1);
      expect(await config.getQualityFactorOverride(), 0.5);
      await config.setQualityFactorOverride(9.0);
      expect(await config.getQualityFactorOverride(), 2.0);
      await config.setQualityFactorOverride(1.25);
      expect(await config.getQualityFactorOverride(), 1.25);
      await config.setQualityFactorOverride(null);
      expect(await config.getQualityFactorOverride(), isNull);
    });

    test('scan folders are trimmed of separators and de-duplicated', () async {
      await config.setScanFoldersOverride(['/DCIM/', 'DCIM', ' Pictures ', '']);
      expect(await config.getScanFoldersOverride(), ['DCIM', 'Pictures']);
    });

    test('an all-blank folder list clears rather than storing nothing',
        () async {
      await config.setScanFoldersOverride(['  ', '//']);
      expect(await config.getScanFoldersOverride(), isNull);
    });

    test('clearOverrides returns every field to inherit', () async {
      await config.setPipelineEnabledOverride(true);
      await config.setThemeIdOverride('t');
      await config.setDefaultCopiesOverride(4);
      await config.setScanFoldersOverride(['Pictures']);
      await config.clearOverrides();
      expect(await config.getPipelineEnabledOverride(), isNull);
      expect(await config.getThemeIdOverride(), isNull);
      expect(await config.getDefaultCopiesOverride(), isNull);
      expect(await config.getScanFoldersOverride(), isNull);
    });
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

    test('clearCachedFlags empties the cache', () async {
      await config.cacheFlags(const EventPipelineFlags(aiEnabled: true));
      await config.clearCachedFlags();
      expect((await config.readCachedFlags()).isEmpty, isTrue);
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

    test('local overrides beat backend flags', () async {
      await config.setAiEnabledOverride(true);
      await config.setDefaultCopiesOverride(5);
      final s = await config.resolve(
        flags: const EventPipelineFlags(aiEnabled: false, defaultCopies: 2),
      );
      expect(s.aiEnabled, isTrue);
      expect(s.defaultCopies, 5);
    });

    test('an override of false still beats a backend true', () async {
      await config.setAiEnabledOverride(false);
      final s = await config.resolve(
        flags: const EventPipelineFlags(aiEnabled: true),
      );
      expect(s.aiEnabled, isFalse);
    });

    test('falls back to cached flags when none are passed', () async {
      await config.cacheFlags(
        const EventPipelineFlags(pipelineEnabled: true, themeId: 'cached'),
      );
      final s = await config.resolve();
      expect(s.pipelineEnabled, isTrue);
      expect(s.themeId, 'cached');
    });

    test('offline mode forces mirroring off despite backend and override',
        () async {
      await config.setMirrorEnabledOverride(true);
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
