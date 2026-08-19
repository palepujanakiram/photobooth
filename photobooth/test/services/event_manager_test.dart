import 'package:flutter_test/flutter_test.dart';
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
      id: 'e1',
      code: 'PARTY',
      photoMode: 'FRAME_ONLY',
      name: 'Gala',
      themeCount: 2,
      frameCount: 3,
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
      id: 'e1',
      code: 'PARTY',
      photoMode: 'BOTH',
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
      id: 'e1',
      code: 'PARTY',
      photoMode: 'BOTH',
      name: 'Named',
    );
    await em.cacheVerifyResult(
      id: 'e1',
      code: 'PARTY',
      photoMode: 'BOTH',
    );
    expect(await em.getEventName(), isNull);
  });
}
