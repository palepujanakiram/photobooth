import 'dart:async';
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
  TestWidgetsFlutterBinding.ensureInitialized();

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
    expect(AppRuntimeConfig.instance.showApiLogs, isTrue);

    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showGenerationCommentary: false),
    );
    await mgr.fetchSettings();
    expect(AppRuntimeConfig.instance.showGenerationCommentary, isTrue);
    expect(AppRuntimeConfig.instance.thermalSafeMode, isTrue);
  });

  test('fetchSettings applies showApiLogs from API', () async {
    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showApiLogs: true),
    );
    final mgr = AppSettingsManager(
      apiService: _SettingsApi(AppSettingsModel(showApiLogs: false)),
      resolveKioskCode: () async => null,
    );
    await mgr.fetchSettings();
    expect(AppRuntimeConfig.instance.showApiLogs, isFalse);
    expect(mgr.settings?.showApiLogs, isFalse);
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

  test('forceRefresh joins an in-flight settings GET', () async {
    final gate = Completer<void>();
    final api = _GatedSettingsApi(AppSettingsModel(initialPrice: 40), gate);
    final mgr = AppSettingsManager(
      apiService: api,
      resolveKioskCode: () async => 'JOIN',
    );
    final first = mgr.fetchSettings(forceRefresh: true);
    final second = mgr.fetchSettings(forceRefresh: true);
    await Future<void>.delayed(Duration.zero);
    expect(api.fetchCount, 1);
    gate.complete();
    await Future.wait([first, second]);
    expect(api.fetchCount, 1);
    expect(mgr.settings?.initialPrice, 40);
  });

  test('forceRefresh after a completed fetch hits the network', () async {
    final api = _SettingsApi(AppSettingsModel(initialPrice: 10));
    final mgr = AppSettingsManager(
      apiService: api,
      resolveKioskCode: () async => null,
    );
    await mgr.fetchSettings();
    expect(api.fetchCount, 1);
    await mgr.fetchSettings(forceRefresh: true);
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
    expect(offline.errorMessage, isNull);

    await offline.fetchSettings(forceRefresh: true);
    expect(offline.settings?.initialPrice, 175);
    expect(offline.errorMessage, isNotNull);
  });

  test('hydrateFromCache loads disk without a network call', () async {
    final dir = await Directory.systemTemp.createTemp('settings_hydrate_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final disk = CatalogDiskCache(resolveDirectory: () async => dir);
    final api = _SettingsApi(AppSettingsModel(initialPrice: 80));
    final first = AppSettingsManager(
      apiService: api,
      resolveKioskCode: () async => 'K2',
      diskCache: disk,
    );
    await first.fetchSettings();
    expect(api.fetchCount, 1);

    final cached = AppSettingsManager(
      apiService: api,
      resolveKioskCode: () async => 'K2',
      diskCache: disk,
    );
    await cached.hydrateFromCache();
    expect(cached.settings?.initialPrice, 80);
    expect(api.fetchCount, 1);
  });

  test('hydrateFromCache then fetchSettings does not hit the network', () async {
    final dir = await Directory.systemTemp.createTemp('settings_hydrate_fetch_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final disk = CatalogDiskCache(resolveDirectory: () async => dir);
    final api = _SettingsApi(AppSettingsModel(initialPrice: 90));
    final first = AppSettingsManager(
      apiService: api,
      resolveKioskCode: () async => 'K2',
      diskCache: disk,
    );
    await first.fetchSettings();
    expect(api.fetchCount, 1);

    final cached = AppSettingsManager(
      apiService: api,
      resolveKioskCode: () async => 'K2',
      diskCache: disk,
    );
    await cached.hydrateFromCache();
    await cached.fetchSettings();
    expect(cached.settings?.initialPrice, 90);
    expect(api.fetchCount, 1);
  });

  test('refreshOnAppResume skips HTTP when no kiosk is bound', () async {
    final api = _SettingsApi(AppSettingsModel(initialPrice: 1));
    final mgr = AppSettingsManager(
      apiService: api,
      resolveKioskCode: () async => null,
    );
    await mgr.refreshOnAppResume();
    expect(api.fetchCount, 0);
    expect(mgr.settings, isNull);
  });

  test('refreshOnAppResume hydrates disk without HTTP when unbound', () async {
    final dir = await Directory.systemTemp.createTemp('settings_resume_disk_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final disk = CatalogDiskCache(resolveDirectory: () async => dir);
    final api = _SettingsApi(AppSettingsModel(initialPrice: 120));
    final bound = AppSettingsManager(
      apiService: api,
      resolveKioskCode: () async => '',
      diskCache: disk,
    );
    await bound.fetchSettings();
    expect(api.fetchCount, 1);

    final resume = AppSettingsManager(
      apiService: api,
      resolveKioskCode: () async => '',
      diskCache: disk,
    );
    await resume.refreshOnAppResume();
    expect(resume.settings?.initialPrice, 120);
    expect(api.fetchCount, 1);
  });

  test('refreshOnAppResume uses cache when a kiosk is bound', () async {
    final api = _SettingsApi(AppSettingsModel(initialPrice: 55));
    final mgr = AppSettingsManager(
      apiService: api,
      resolveKioskCode: () async => 'GSM',
    );
    await mgr.fetchSettings();
    expect(api.fetchCount, 1);
    await mgr.refreshOnAppResume();
    expect(api.fetchCount, 1);
  });

  test('hydrateFromCache no-ops when disk is empty', () async {
    final dir = await Directory.systemTemp.createTemp('settings_hydrate_empty_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final api = _SettingsApi(AppSettingsModel(initialPrice: 1));
    final mgr = AppSettingsManager(
      apiService: api,
      resolveKioskCode: () async => 'K3',
      diskCache: CatalogDiskCache(resolveDirectory: () async => dir),
    );
    await mgr.hydrateFromCache();
    expect(mgr.settings, isNull);
    expect(api.fetchCount, 0);
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

class _GatedSettingsApi extends FakeApiService {
  _GatedSettingsApi(this.model, this.gate);

  final AppSettingsModel model;
  final Completer<void> gate;
  int fetchCount = 0;

  @override
  Future<AppSettingsModel> getAppSettings() async {
    fetchCount++;
    await gate.future;
    return model;
  }
}
