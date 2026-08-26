import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/catalog_disk_cache.dart';
import 'package:photobooth/services/event_manager.dart';
import 'package:photobooth/services/theme_manager.dart';
import 'package:photobooth/models/event_info_model.dart';
import 'package:photobooth/screens/splash/app_splash_event_helpers.dart';
import 'package:photobooth/utils/exceptions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/theme_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'kiosk_code': 'K1'});
  });

  test('fetchThemes caches and returns active themes', () async {
    final tm = ThemeManager.forTesting(ThemesFakeApi([sampleTheme('t1')]));
    final first = await tm.fetchThemes();
    expect(first, hasLength(1));
    expect(tm.hasThemes, isTrue);
    expect(tm.getActiveThemes(), hasLength(1));
    expect(tm.getThemeById('t1')?.id, 't1');
    expect(tm.getSampleImageUrls(), isNotEmpty);
  });

  test('fetchThemes returns cache without second network call', () async {
    final api = ThemesFakeApi([sampleTheme('t1')]);
    final tm = ThemeManager.forTesting(api);
    await tm.fetchThemes();
    await tm.fetchThemes();
    expect(tm.themes, hasLength(1));
  });

  test('fetchThemes forceRefresh after error', () async {
    final tm = ThemeManager.forTesting(ThemesFakeApi([sampleTheme('t1')]));
    await tm.fetchThemes();
    final failing = ThemeManager.forTesting(
      ThemesFakeApi([sampleTheme('t1')], throwOnFetch: true),
    );
    await expectLater(failing.fetchThemes(), throwsA(isA<ApiException>()));
    final refreshed = await tm.fetchThemes(forceRefresh: true);
    expect(refreshed, hasLength(1));
  });

  test('clearCache notifies listeners', () async {
    final tm = ThemeManager.forTesting(ThemesFakeApi([sampleTheme('t1')]));
    await tm.fetchThemes();
    var notified = false;
    tm.addListener(() => notified = true);
    tm.clearCache();
    expect(notified, isTrue);
    expect(tm.hasThemes, isFalse);
  });

  test('fetchThemes rethrows when empty and API fails', () async {
    final tm = ThemeManager.forTesting(ThemesFakeApi([], throwOnFetch: true));
    expect(() => tm.fetchThemes(), throwsA(isA<ApiException>()));
  });

  test('fetchThemes hydrates disk then falls back when API fails', () async {
    final dir = await Directory.systemTemp.createTemp('themes_disk_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final disk = CatalogDiskCache(resolveDirectory: () async => dir);
    final first = ThemeManager.forTesting(
      ThemesFakeApi([sampleTheme('t1')]),
      diskCache: disk,
    );
    await first.fetchThemes();

    final offline = ThemeManager.forTesting(
      ThemesFakeApi([], throwOnFetch: true),
      diskCache: disk,
    );
    final loaded = await offline.fetchThemes();
    expect(loaded.single.id, 't1');
  });

  test('cached event bind keeps event themes available when Dio fails',
      () async {
    final dir = await Directory.systemTemp.createTemp('event_catalog_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final disk = CatalogDiskCache(resolveDirectory: () async => dir);
    final eventManager = EventManager(diskCache: disk);
    await bindSplashEventCode(
      eventManager: eventManager,
      fetchEvent: (_, __) async => const EventInfoModel(
        id: 'event-1',
        code: 'GALA',
        themeCount: 1,
        themeIds: ['t1'],
      ),
      eventCode: 'GALA',
      kioskCode: 'K1',
    );
    await ThemeManager.forTesting(
      ThemesFakeApi([sampleTheme('t1')]),
      diskCache: disk,
    ).fetchThemes();

    SharedPreferences.setMockInitialValues({'kiosk_code': 'K1'});
    EventManager.resetCacheForTests();
    final rebound = EventManager(diskCache: disk);
    expect(
      await bindSplashEventCode(
        eventManager: rebound,
        fetchEvent: (_, __) async => null,
        eventCode: 'GALA',
        kioskCode: 'K1',
      ),
      isNull,
    );
    final themes = await ThemeManager.forTesting(
      ThemesFakeApi([], throwOnFetch: true),
      diskCache: disk,
    ).fetchThemes();
    expect(themes.single.id, 't1');
  });
}
