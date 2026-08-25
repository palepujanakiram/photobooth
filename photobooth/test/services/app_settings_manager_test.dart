import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/services/app_settings_manager.dart';
import 'package:photobooth/services/catalog_disk_cache.dart';
import 'package:photobooth/services/offline_operator_pin_store.dart';
import 'package:photobooth/utils/app_runtime_config.dart';
import 'package:photobooth/utils/exceptions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_api_service.dart';

class _SettingsApi extends FakeApiService {
  _SettingsApi(this.model);

  AppSettingsModel model;
  int fetchCount = 0;

  @override
  Future<AppSettingsModel> getAppSettings() async {
    fetchCount++;
    return model;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OfflineOperatorPinStore.resetCacheForTests();
  });

  test('fetchSettings caches and resolveParallelImageCount', () async {
    final api = _SettingsApi(AppSettingsModel(parallelImageCount: 3));
    final mgr = AppSettingsManager(
      apiService: api,
      resolveKioskCode: () async => null,
    );
    await mgr.fetchSettings();
    expect(mgr.hasSettings, isTrue);
    expect(mgr.resolveParallelImageCount(), 3);
    await mgr.fetchSettings();
    expect(api.fetchCount, 1);
    expect(mgr.isLoading, isFalse);
  });

  test('cached fetchSettings reapplies AppRuntimeConfig', () async {
    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showGenerationCommentary: false),
    );
    final mgr = AppSettingsManager(
      apiService: _SettingsApi(
        AppSettingsModel(showGenerationCommentary: true, thermalSafeMode: true),
      ),
      resolveKioskCode: () async => null,
    );
    await mgr.fetchSettings();
    expect(AppRuntimeConfig.instance.showGenerationCommentary, isTrue);
    expect(AppRuntimeConfig.instance.thermalSafeMode, isTrue);

    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showGenerationCommentary: false),
    );
    await mgr.fetchSettings();
    expect(AppRuntimeConfig.instance.showGenerationCommentary, isTrue);
    expect(AppRuntimeConfig.instance.thermalSafeMode, isTrue);
  });

  test('fetchSettings records error string', () async {
    final mgr = AppSettingsManager(
      apiService: _ThrowingSettingsApi(),
      resolveKioskCode: () async => null,
    );
    await mgr.fetchSettings();
    expect(mgr.errorMessage, isNotNull);
  });

  test('refetches when bound kiosk code changes', () async {
    String? kiosk;
    final api = _SettingsApi(AppSettingsModel(initialPrice: 100));
    final mgr = AppSettingsManager(
      apiService: api,
      resolveKioskCode: () async => kiosk,
    );

    await mgr.fetchSettings();
    expect(api.fetchCount, 1);
    expect(mgr.settings?.initialPrice, 100);

    // Same unbound kiosk → still cached.
    await mgr.fetchSettings();
    expect(api.fetchCount, 1);

    // Splash binds a kiosk → must refetch effective guest prices.
    kiosk = 'KIOSK1';
    api.model = AppSettingsModel(initialPrice: 250);
    await mgr.fetchSettings();
    expect(api.fetchCount, 2);
    expect(mgr.settings?.initialPrice, 250);

    // Same kiosk again → cached.
    await mgr.fetchSettings();
    expect(api.fetchCount, 2);
  });

  test('fetchSettings hydrates disk when API fails', () async {
    final dir = await Directory.systemTemp.createTemp('settings_disk_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final disk = CatalogDiskCache(resolveDirectory: () async => dir);
    final api = _SettingsApi(AppSettingsModel(initialPrice: 175));
    final first = AppSettingsManager(
      apiService: api,
      resolveKioskCode: () async => 'K1',
      diskCache: disk,
    );
    await first.fetchSettings();
    expect(first.settings?.initialPrice, 175);

    final offline = AppSettingsManager(
      apiService: _ThrowingSettingsApi(),
      resolveKioskCode: () async => 'K1',
      diskCache: disk,
    );
    await offline.fetchSettings();
    expect(offline.settings?.initialPrice, 175);
    expect(offline.errorMessage, isNotNull);
  });

  test('fetchSettings syncs offlineCashPins into pin store', () async {
    final api = _SettingsApi(
      AppSettingsModel(offlineCashPins: const ['1357']),
    );
    final mgr = AppSettingsManager(
      apiService: api,
      resolveKioskCode: () async => null,
    );
    await mgr.fetchSettings();
    expect(await OfflineOperatorPinStore.verifyPin('1357'), isTrue);
    expect(await OfflineOperatorPinStore.verifyPin('2468'), isTrue);
  });
}

class _ThrowingSettingsApi extends FakeApiService {
  @override
  Future<AppSettingsModel> getAppSettings() async {
    throw ApiException('settings failed');
  }
}
