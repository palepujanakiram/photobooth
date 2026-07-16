import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/services/app_settings_manager.dart';
import 'package:photobooth/utils/app_runtime_config.dart';
import 'package:photobooth/utils/exceptions.dart';

import '../fakes/fake_api_service.dart';

class _SettingsApi extends FakeApiService {
  _SettingsApi(this.model, {this.onFetch});

  AppSettingsModel model;
  int fetchCount = 0;
  void Function()? onFetch;

  @override
  Future<AppSettingsModel> getAppSettings() async {
    fetchCount++;
    onFetch?.call();
    return model;
  }
}

void main() {
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
}

class _ThrowingSettingsApi extends FakeApiService {
  @override
  Future<AppSettingsModel> getAppSettings() async {
    throw ApiException('settings failed');
  }
}
