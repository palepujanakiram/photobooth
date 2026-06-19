import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/services/app_settings_manager.dart';
import 'package:photobooth/utils/app_runtime_config.dart';
import 'package:photobooth/utils/exceptions.dart';

import '../fakes/fake_api_service.dart';

class _SettingsApi extends FakeApiService {
  _SettingsApi(this.model);

  final AppSettingsModel model;

  @override
  Future<AppSettingsModel> getAppSettings() async => model;
}

void main() {
  test('fetchSettings caches and resolveParallelImageCount', () async {
    final mgr = AppSettingsManager(
      apiService: _SettingsApi(
        AppSettingsModel(parallelImageCount: 3),
      ),
    );
    await mgr.fetchSettings();
    expect(mgr.hasSettings, isTrue);
    expect(mgr.resolveParallelImageCount(), 3);
    await mgr.fetchSettings();
    expect(mgr.isLoading, isFalse);
  });

  test('cached fetchSettings reapplies AppRuntimeConfig', () async {
    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showGenerationCommentary: false),
    );
    final mgr = AppSettingsManager(
      apiService: _SettingsApi(
        AppSettingsModel(showGenerationCommentary: true),
      ),
    );
    await mgr.fetchSettings();
    expect(AppRuntimeConfig.instance.showGenerationCommentary, isTrue);

    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showGenerationCommentary: false),
    );
    await mgr.fetchSettings();
    expect(AppRuntimeConfig.instance.showGenerationCommentary, isTrue);
  });

  test('fetchSettings records error string', () async {
    final mgr = AppSettingsManager(
      apiService: _ThrowingSettingsApi(),
    );
    await mgr.fetchSettings();
    expect(mgr.errorMessage, isNotNull);
  });
}

class _ThrowingSettingsApi extends FakeApiService {
  @override
  Future<AppSettingsModel> getAppSettings() async {
    throw ApiException('settings failed');
  }
}
