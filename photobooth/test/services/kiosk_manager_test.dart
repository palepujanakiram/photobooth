import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/kiosk_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await KioskManager().clearPaymentEnabledOverride();
    await KioskManager().clearClassicPhotosEnabled();
    await KioskManager().clearOperatingModeOffline();
    await KioskManager().clearKioskCode();
    KioskManager.resetPaymentOverrideCacheForTests();
    KioskManager.resetClassicPhotosCacheForTests();
    KioskManager.resetOperatingModeCacheForTests();
  });

  test('payment override and clear flows', () async {
    SharedPreferences.setMockInitialValues({});
    final km = KioskManager();
    expect(await km.getPaymentEnabledOverride(), isNull);
    await km.setPaymentEnabledOverride(true);
    expect(await km.getPaymentEnabledOverride(), isTrue);
    await km.clearPaymentEnabledOverride();
    expect(await km.getPaymentEnabledOverride(), isNull);
    await km.setKioskCode('abc');
    expect(await km.getKioskCode(), 'ABC');
    await km.clearKioskCode();
    expect(await km.getKioskCode(), isNull);
    await km.setKioskCode('  ');
    expect(await km.getKioskCode(), isNull);
    await km.setPaymentEnabledOverride(null);
    expect(await km.getPaymentEnabledOverride(), isNull);
  });

  test('getPaymentEnabledOverride reads prefs when cache empty', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('kiosk_payment_enabled_override', false);
    KioskManager.resetPaymentOverrideCacheForTests();
    expect(await KioskManager().getPaymentEnabledOverride(), isFalse);
  });

  test('classic photos defaults true and persists', () async {
    final km = KioskManager();
    expect(await km.isClassicPhotosEnabled(), isTrue);
    await km.setClassicPhotosEnabled(false);
    expect(await km.isClassicPhotosEnabled(), isFalse);
    KioskManager.resetClassicPhotosCacheForTests();
    expect(await km.isClassicPhotosEnabled(), isFalse);
    await km.clearClassicPhotosEnabled();
    KioskManager.resetClassicPhotosCacheForTests();
    expect(await km.isClassicPhotosEnabled(), isTrue);
  });

  test('operating mode defaults online and persists offline', () async {
    final km = KioskManager();
    expect(await km.isOperatingModeOffline(), isFalse);
    expect(KioskManager.isOperatingModeOfflineCached, isFalse);
    await km.setOperatingModeOffline(true);
    expect(await km.isOperatingModeOffline(), isTrue);
    expect(KioskManager.isOperatingModeOfflineCached, isTrue);
    KioskManager.resetOperatingModeCacheForTests();
    expect(await km.isOperatingModeOffline(), isTrue);
    await km.clearOperatingModeOffline();
    KioskManager.resetOperatingModeCacheForTests();
    expect(await km.isOperatingModeOffline(), isFalse);
  });

  test('isOperatingModeOffline reads prefs when cache empty', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('kiosk_operating_mode_offline', true);
    KioskManager.resetOperatingModeCacheForTests();
    expect(await KioskManager().isOperatingModeOffline(), isTrue);
  });
}
