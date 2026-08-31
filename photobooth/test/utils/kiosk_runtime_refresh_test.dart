import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/models/kiosk_info_model.dart';
import 'package:photobooth/services/app_settings_manager.dart';
import 'package:photobooth/services/kiosk_manager.dart';
import 'package:photobooth/utils/kiosk_runtime_refresh.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await KioskManager().clearClassicPhotosEnabled();
    await KioskManager().clearOperatingModeOffline();
    await KioskManager().clearKioskCode();
    KioskManager.resetClassicPhotosCacheForTests();
    KioskManager.resetOperatingModeCacheForTests();
  });

  test('refreshBoundKioskAppSettings force-refreshes cached settings', () async {
    final api = _CountingSettingsApi(
      AppSettingsModel(enableOsdScrub: false, initialPrice: 100),
    );
    final mgr = AppSettingsManager(
      apiService: api,
      resolveKioskCode: () async => 'FOTO',
    );
    await mgr.fetchSettings();
    expect(api.fetchCount, 1);
    expect(mgr.settings?.enableOsdScrub, isFalse);

    api.model = AppSettingsModel(enableOsdScrub: true, initialPrice: 250);
    await refreshBoundKioskAppSettings(settings: mgr);
    expect(api.fetchCount, 2);
    expect(mgr.settings?.enableOsdScrub, isTrue);
    expect(mgr.settings?.initialPrice, 250);
  });

  test('refreshBoundKioskAppSettings fail-opens on timeout', () async {
    final api = _ThenHangSettingsApi();
    final mgr = AppSettingsManager(
      apiService: api,
      resolveKioskCode: () async => 'FOTO',
    );
    await mgr.fetchSettings();
    expect(mgr.settings?.enableOsdScrub, isTrue);

    await refreshBoundKioskAppSettings(
      settings: mgr,
      timeout: const Duration(milliseconds: 20),
    );
    expect(mgr.settings?.enableOsdScrub, isTrue);
  });

  test('refreshBoundKioskAppSettings fail-opens when fetch throws', () async {
    final mgr = _ThrowingSettingsManager();
    await refreshBoundKioskAppSettings(
      settings: mgr,
      timeout: const Duration(seconds: 1),
    );
    expect(mgr.hasSettings, isFalse);
  });

  test('refreshKioskRuntimeConfig skips when splash just fetched settings',
      () async {
    final km = KioskManager();
    await km.setKioskCode('FOTO');
    await km.setClassicPhotosEnabled(false);

    final api = _RuntimeApi(
      settings: AppSettingsModel(enableOsdScrub: true),
      kiosk: const KioskInfoModel(
        id: 'k1',
        code: 'FOTO',
        classicPhotosEnabled: true,
      ),
    );
    final mgr = AppSettingsManager(
      apiService: api,
      resolveKioskCode: () async => 'FOTO',
    );
    await mgr.fetchSettings();
    expect(api.settingsFetches, 1);

    final result = await refreshKioskRuntimeConfig(
      settings: mgr,
      api: api,
      kiosk: km,
    );
    expect(result.classicPhotosEnabled, isFalse);
    expect(api.settingsFetches, 1);
    expect(api.kioskFetches, 0);
  });

  test('refreshKioskRuntimeConfig refreshes when onlyIfStale is false',
      () async {
    final km = KioskManager();
    await km.setKioskCode('FOTO');
    await km.setClassicPhotosEnabled(false);

    final api = _RuntimeApi(
      settings: AppSettingsModel(enableOsdScrub: true),
      kiosk: const KioskInfoModel(
        id: 'k1',
        code: 'FOTO',
        classicPhotosEnabled: true,
      ),
    );
    final mgr = AppSettingsManager(
      apiService: api,
      resolveKioskCode: () async => 'FOTO',
    );
    await mgr.fetchSettings();
    api.settings = AppSettingsModel(enableOsdScrub: false);
    expect(api.settingsFetches, 1);

    final result = await refreshKioskRuntimeConfig(
      settings: mgr,
      api: api,
      kiosk: km,
      onlyIfStale: false,
    );
    expect(result.classicPhotosEnabled, isTrue);
    expect(await km.isClassicPhotosEnabled(), isTrue);
    expect(await km.isOperatingModeOffline(), isFalse);
    expect(mgr.settings?.enableOsdScrub, isFalse);
    expect(api.settingsFetches, 2);
    expect(api.kioskFetches, 1);
  });

  test('refreshKioskRuntimeConfig fetches when settings are stale', () async {
    final km = KioskManager();
    await km.setKioskCode('FOTO');
    await km.setClassicPhotosEnabled(false);

    final api = _RuntimeApi(
      settings: AppSettingsModel(enableOsdScrub: true),
      kiosk: const KioskInfoModel(
        id: 'k1',
        code: 'FOTO',
        classicPhotosEnabled: true,
      ),
    );
    final mgr = AppSettingsManager(
      apiService: api,
      resolveKioskCode: () async => 'FOTO',
    );

    final result = await refreshKioskRuntimeConfig(
      settings: mgr,
      api: api,
      kiosk: km,
    );
    expect(result.classicPhotosEnabled, isTrue);
    expect(api.settingsFetches, 1);
    expect(api.kioskFetches, 1);
  });

  test('refreshKioskRuntimeConfig refetches after kiosk code changes', () async {
    final km = KioskManager();
    await km.setKioskCode('OLD');
    await km.setClassicPhotosEnabled(false);

    final api = _RuntimeApi(
      settings: AppSettingsModel(enableOsdScrub: true),
      kiosk: const KioskInfoModel(
        id: 'k2',
        code: 'NEW',
        classicPhotosEnabled: true,
      ),
    );
    final mgr = AppSettingsManager(
      apiService: api,
      resolveKioskCode: km.getKioskCode,
    );
    await mgr.fetchSettings();
    expect(api.settingsFetches, 1);

    await km.setKioskCode('NEW');
    final result = await refreshKioskRuntimeConfig(
      settings: mgr,
      api: api,
      kiosk: km,
    );
    expect(result.classicPhotosEnabled, isTrue);
    expect(api.settingsFetches, 2);
    expect(api.kioskFetches, 1);
  });

  test('refreshBoundKioskAppSettings onlyIfStale skips a fresh fetch', () async {
    final api = _CountingSettingsApi(
      AppSettingsModel(enableOsdScrub: false, initialPrice: 100),
    );
    final mgr = AppSettingsManager(
      apiService: api,
      resolveKioskCode: () async => 'FOTO',
    );
    await mgr.fetchSettings();
    expect(api.fetchCount, 1);

    await refreshBoundKioskAppSettings(settings: mgr, onlyIfStale: true);
    expect(api.fetchCount, 1);
  });

  test('isBoundKioskSettingsFresh uses ttl and missing timestamps', () {
    expect(
      isBoundKioskSettingsFresh(lastFetchedAt: null, hasSettings: true),
      isFalse,
    );
    expect(
      isBoundKioskSettingsFresh(
        lastFetchedAt: DateTime(2026, 1, 1, 12),
        hasSettings: false,
      ),
      isFalse,
    );
    expect(
      isBoundKioskSettingsFresh(
        lastFetchedAt: DateTime(2026, 1, 1, 12),
        hasSettings: true,
        now: () => DateTime(2026, 1, 1, 12, 1),
      ),
      isTrue,
    );
    expect(
      isBoundKioskSettingsFresh(
        lastFetchedAt: DateTime(2026, 1, 1, 12),
        hasSettings: true,
        now: () => DateTime(2026, 1, 1, 12, 3),
      ),
      isFalse,
    );
    expect(
      isBoundKioskSettingsFresh(
        lastFetchedAt: DateTime(2026, 1, 1, 12),
        hasSettings: true,
        fetchedKioskKey: 'GSM',
        boundKioskKey: 'OTHER',
        now: () => DateTime(2026, 1, 1, 12, 1),
      ),
      isFalse,
    );
    expect(
      isBoundKioskSettingsFresh(
        lastFetchedAt: DateTime(2026, 1, 1, 12),
        hasSettings: true,
        fetchedKioskKey: 'gsm',
        boundKioskKey: 'GSM',
        now: () => DateTime(2026, 1, 1, 12, 1),
      ),
      isTrue,
    );
  });
}

class _CountingSettingsApi extends FakeApiService {
  _CountingSettingsApi(this.model);

  AppSettingsModel model;
  int fetchCount = 0;

  @override
  Future<AppSettingsModel> getAppSettings() async {
    fetchCount++;
    return model;
  }
}

class _ThenHangSettingsApi extends FakeApiService {
  int fetchCount = 0;

  @override
  Future<AppSettingsModel> getAppSettings() async {
    fetchCount++;
    if (fetchCount == 1) {
      return AppSettingsModel(enableOsdScrub: true);
    }
    return Completer<AppSettingsModel>().future;
  }
}

class _ThrowingSettingsManager extends AppSettingsManager {
  _ThrowingSettingsManager()
      : super(
          apiService: FakeApiService(),
          resolveKioskCode: () async => null,
        );

  @override
  Future<void> fetchSettings({bool forceRefresh = false}) {
    throw StateError('forced settings failure');
  }
}

class _RuntimeApi extends FakeApiService {
  _RuntimeApi({required this.settings, required this.kiosk});

  AppSettingsModel settings;
  final KioskInfoModel kiosk;
  int settingsFetches = 0;
  int kioskFetches = 0;

  @override
  Future<AppSettingsModel> getAppSettings() async {
    settingsFetches++;
    return settings;
  }

  @override
  Future<KioskInfoModel?> fetchKioskByCode(String kioskCode) async {
    kioskFetches++;
    return kiosk;
  }
}
