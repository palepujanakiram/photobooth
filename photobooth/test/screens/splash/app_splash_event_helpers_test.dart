import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_info_model.dart';
import 'package:photobooth/screens/splash/app_splash_event_helpers.dart';
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

  test('empty event code is a no-op', () async {
    final err = await bindSplashEventCode(
      eventManager: EventManager(),
      fetchEvent: (_, __) async => throw StateError('should not fetch'),
      eventCode: '  ',
      kioskCode: 'K1',
    );
    expect(err, isNull);
    expect(await EventManager().getEventCode(), isNull);
  });

  test('invalid event returns error', () async {
    final err = await bindSplashEventCode(
      eventManager: EventManager(),
      fetchEvent: (_, __) async => null,
      eventCode: 'NOPE',
      kioskCode: 'K1',
    );
    expect(err, isNotNull);
  });

  test('valid event is cached', () async {
    const info = EventInfoModel(
      id: 'e1',
      code: 'WED',
      photoMode: 'BOTH',
      themeCount: 3,
    );
    final err = await bindSplashEventCode(
      eventManager: EventManager(),
      fetchEvent: (code, kiosk) async {
        expect(code, 'WED');
        expect(kiosk, 'K1');
        return info;
      },
      eventCode: 'wed',
      kioskCode: 'K1',
    );
    expect(err, isNull);
    expect(await EventManager().getEventCode(), 'WED');
    expect(await EventManager().getThemeCount(), 3);
  });

  test('inactive or invalid event returns error', () async {
    const inactive = EventInfoModel(
      id: 'e1',
      code: 'OLD',
      currentlyActive: false,
    );
    expect(
      await bindSplashEventCode(
        eventManager: EventManager(),
        fetchEvent: (_, __) async => inactive,
        eventCode: 'OLD',
        kioskCode: 'K1',
      ),
      isNotNull,
    );

    const invalid = EventInfoModel(id: '', code: 'X');
    expect(
      await bindSplashEventCode(
        eventManager: EventManager(),
        fetchEvent: (_, __) async => invalid,
        eventCode: 'X',
        kioskCode: 'K1',
      ),
      isNotNull,
    );
  });

  test('offline resume when same event already cached locally', () async {
    final mgr = EventManager();
    await mgr.cacheVerifyResult(
      id: 'e1',
      code: 'WED',
      photoMode: 'BOTH',
      themeCount: 2,
    );
    final err = await bindSplashEventCode(
      eventManager: mgr,
      fetchEvent: (_, __) async => null,
      eventCode: 'wed',
      kioskCode: 'K1',
    );
    expect(err, isNull);
    expect(await mgr.getEventCode(), 'WED');
  });
}
