import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_info_model.dart';
import 'package:photobooth/services/catalog_disk_cache.dart';
import 'package:photobooth/services/event_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    EventManager.resetCacheForTests();
    await EventManager().clearEvent();
    EventManager.resetCacheForTests();
  });

  test('set and get event code uppercases', () async {
    final em = EventManager();
    expect(await em.getEventCode(), isNull);
    await em.setEventCode(' wed-01 ');
    expect(await em.getEventCode(), 'WED-01');
  });

  test('cacheVerifyResult persists photoMode and counts', () async {
    final em = EventManager();
    await em.cacheVerifyResult(
      const EventInfoModel(
        id: 'e1',
        code: 'PARTY',
        photoMode: 'FRAME_ONLY',
        name: 'Gala',
        catalog: EventInfoCatalog(themeCount: 2, frameCount: 3),
      ),
    );
    EventManager.resetCacheForTests();
    expect(await em.getEventCode(), 'PARTY');
    expect(await em.getEventId(), 'e1');
    expect(await em.getPhotoModeOverride(), 'FRAME_ONLY');
    expect(await em.getThemeCount(), 2);
    expect(await em.getFrameCount(), 3);
    expect(await em.getEventName(), 'Gala');
  });

  test('station role and device id persist', () async {
    final em = EventManager();
    expect(await em.isEventBound(), isFalse);
    expect(await em.getStationRole(), isNull);
    await em.setStationRole('CAPTURE');
    expect(await em.getStationRole(), 'capture');
    EventManager.resetCacheForTests();
    expect(await em.getStationRole(), 'capture');
    final id = await em.getOrCreateDeviceId();
    expect(id, isNotEmpty);
    expect(await em.getOrCreateDeviceId(), id);
    await em.setStationRole('nope');
    expect(await em.getStationRole(), isNull);
  });

  test('clearEvent wipes prefs', () async {
    final em = EventManager();
    await em.cacheVerifyResult(
      const EventInfoModel(
        id: 'e1',
        code: 'PARTY',
        photoMode: 'BOTH',
      ),
    );
    await em.setStationRole('print');
    await em.clearEvent();
    EventManager.resetCacheForTests();
    expect(await em.getEventCode(), isNull);
    expect(await em.getPhotoModeOverride(), isNull);
    expect(await em.getEventId(), isNull);
    expect(await em.getThemeCount(), 0);
    expect(await em.getFrameCount(), 0);
    expect(await em.getEventName(), isNull);
    expect(await em.getStationRole(), isNull);
  });

  test('setEventCode empty and setPhotoModeOverride clear values', () async {
    final em = EventManager();
    await em.setEventCode('ABC');
    await em.setPhotoModeOverride('BOTH');
    expect(await em.getEventCode(), 'ABC');
    expect(await em.getPhotoModeOverride(), 'BOTH');
    await em.setEventCode(null);
    await em.setPhotoModeOverride('');
    expect(await em.getEventCode(), isNull);
    expect(await em.getPhotoModeOverride(), isNull);
  });

  test('getEventCode and photoMode use in-memory cache', () async {
    final em = EventManager();
    await em.setEventCode('CACHED');
    await em.setPhotoModeOverride('AI_TRANSFORM');
    expect(await em.getEventCode(), 'CACHED');
    expect(await em.getPhotoModeOverride(), 'AI_TRANSFORM');
  });

  test('cacheVerifyResult without name removes stored name', () async {
    final em = EventManager();
    await em.cacheVerifyResult(
      const EventInfoModel(
        id: 'e1',
        code: 'PARTY',
        photoMode: 'BOTH',
        name: 'Named',
      ),
    );
    await em.cacheVerifyResult(
      const EventInfoModel(
        id: 'e1',
        code: 'PARTY',
        photoMode: 'BOTH',
      ),
    );
    expect(await em.getEventName(), isNull);
  });

  test('cacheVerifyResult persists chrome and readBoundEvent', () async {
    final dir = await Directory.systemTemp.createTemp();
    final em = EventManager(
      diskCache: CatalogDiskCache(resolveDirectory: () async => dir),
    );
    await em.cacheVerifyResult(
      const EventInfoModel(
        id: 'e1',
        code: 'PARTY',
        photoMode: 'BOTH',
        chrome: EventChrome(
          outputMode: 'DIGITAL_ONLY',
          skin: EventSkinChrome(
            id: 'corporate-navy',
            name: 'Corporate navy',
            bannerFrom: '#1B3A5F',
            bannerTo: '#0E7490',
            ink: '#FFFFFF',
          ),
        ),
      ),
    );
    final bound = await em.readBoundEvent();
    expect(bound?.outputMode, 'DIGITAL_ONLY');
    expect(bound?.chrome.skin.id, 'corporate-navy');
    expect(await em.isEventBound(), isTrue);
    await em.clearEvent();
    EventManager.resetCacheForTests();
    expect(await em.readBoundEvent(), isNull);
  });

  test('readBoundEvent uses prefs when disk cache is unavailable', () async {
    final em = EventManager(
      diskCache: CatalogDiskCache(
        resolveDirectory: () async => throw StateError('no disk'),
      ),
    );
    await em.setEventCode('GALA-01');
    expect(await em.readBoundEvent(), isNull);

    await em.cacheVerifyResult(
      const EventInfoModel(
        id: 'e1',
        code: 'GALA-01',
        name: 'Priya & Arjun',
        photoMode: 'BOTH',
        chrome: EventChrome(
          tagline: 'Wedding celebration',
          skin: EventSkinChrome(id: 'wedding-gold'),
        ),
      ),
    );
    EventManager.resetCacheForTests();
    final bound = await em.readBoundEvent();
    expect(bound?.name, 'Priya & Arjun');
    expect(bound?.chrome.skin.id, 'wedding-gold');
    expect(bound?.description, 'Wedding celebration');

    await em.setEventCode('OTHER');
    expect(await em.readBoundEvent(), isNull);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('event_bound_json', '{');
    await em.setEventCode('GALA-01');
    EventManager.resetCacheForTests();
    expect(await em.readBoundEvent(), isNull);

    await prefs.setString('event_bound_json', '   ');
    EventManager.resetCacheForTests();
    expect(await em.readBoundEvent(), isNull);
  });

  test('hydrateBoundEvent uses cache and does not fetch', () async {
    final em = EventManager(
      diskCache: CatalogDiskCache(
        resolveDirectory: () async => throw StateError('no disk'),
      ),
    );
    await em.cacheVerifyResult(
      const EventInfoModel(id: 'e1', code: 'PARTY', photoMode: 'BOTH'),
    );
    var fetched = 0;
    final bound = await em.hydrateBoundEvent(
      fetchLive: (code) async {
        fetched += 1;
        return null;
      },
    );
    expect(fetched, 0);
    expect(bound?.code, 'PARTY');
  });

  test('hydrateBoundEvent fetches when prefs have only the code', () async {
    final em = EventManager(
      diskCache: CatalogDiskCache(
        resolveDirectory: () async => throw StateError('no disk'),
      ),
    );
    expect(await em.hydrateBoundEvent(), isNull);
    await em.setEventCode('GALA-01');
    expect(await em.hydrateBoundEvent(), isNull);

    var fetchedCode = '';
    final bound = await em.hydrateBoundEvent(
      fetchLive: (code) async {
        fetchedCode = code;
        return const EventInfoModel(
          id: 'e1',
          code: 'GALA-01',
          name: 'Priya & Arjun',
          chrome: EventChrome(skin: EventSkinChrome(id: 'wedding-gold')),
        );
      },
    );
    expect(fetchedCode, 'GALA-01');
    expect(bound?.name, 'Priya & Arjun');
    expect((await em.readBoundEvent())?.chrome.skin.id, 'wedding-gold');
  });

  test('hydrateBoundEvent ignores failed or invalid live fetches', () async {
    final em = EventManager(
      diskCache: CatalogDiskCache(
        resolveDirectory: () async => throw StateError('no disk'),
      ),
    );
    await em.setEventCode('GALA-01');
    expect(await em.hydrateBoundEvent(fetchLive: (_) async => null), isNull);
    expect(
      await em.hydrateBoundEvent(
        fetchLive: (_) async => throw StateError('net'),
      ),
      isNull,
    );
    expect(
      await em.hydrateBoundEvent(
        fetchLive: (_) async => const EventInfoModel(id: '', code: 'GALA-01'),
      ),
      isNull,
    );
  });
}
