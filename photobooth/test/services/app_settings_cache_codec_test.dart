import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/services/app_settings_cache_codec.dart';

void main() {
  test('round-trips guest-critical settings', () {
    final src = AppSettingsModel(
      id: 's1',
      accountId: 'a1',
      maxRegenerations: 3,
      freeRegenerations: 1,
      regenerationPrice: 50,
      regenerationApprovalRequired: true,
      initialPrice: 150,
      additionalPrintPrice: 40,
      printLayout: 'single',
      upscaleEnabled: true,
      upscaleScale: 2,
      upscaleUseAI: false,
      compressionQuality: 85,
      compressionMaxDimension: 1536,
      showGenerationCommentary: false,
      thermalSafeMode: true,
      defaultAiProvider: 'gemini',
      fallbackAiProvider: 'openai',
      enableControlNet: false,
      enableInstantId: false,
      instantIdStrength: 1,
      enableFluxKontext: false,
      activeLanguages: const ['en'],
      photoUploadAllowed: true,
      printerEnabled: true,
      printerHost: '10.0.0.8',
      printerPort: 80,
      printerPath: '/',
      printerTransport: 'auto',
      cameraEnabled: true,
      cameraConnectionMode: 'direct',
      cameraSidecarHost: '127.0.0.1',
      cameraSidecarPort: 8791,
      cameraSidecarPath: '/',
      cameraLivePreviewEnabled: true,
      receiptPrinterEnabled: false,
      receiptPrinterHost: '10.0.0.9',
      receiptPrinterPort: 9100,
      wcmPlusEnabled: false,
      wcmPlusPath: '/wcm',
      parallelImageCount: 2,
      targetFraming: 'close',
      showFramingGuide: true,
      paymentGatewayEnabled: false,
      paymentGatewayEnvironment: 'production',
      paymentCollectionTiming: 'after_generation',
      watermarkEnabled: false,
      exifStampEnabled: true,
      c2paSigningEnabled: false,
      enableOsdScrub: true,
      injectAfMarkers: false,
      enableSurpriseMeAi: true,
      createdAt: DateTime.utc(2026, 8, 23),
      updatedAt: DateTime.utc(2026, 8, 23),
    );
    final json = appSettingsToCacheJson(src);
    final back = appSettingsFromCacheJson(json);
    expect(back, isNotNull);
    expect(back!.initialPrice, 150);
    expect(back.parallelImageCount, 2);
    expect(back.printerHost, '10.0.0.8');
    expect(back.enableOsdScrub, isTrue);
    expect(back.enableSurpriseMeAi, isTrue);
    expect(back.id, 's1');
  });

  test('fromCacheJson rejects non-maps', () {
    expect(appSettingsFromCacheJson(null), isNull);
    expect(appSettingsFromCacheJson('nope'), isNull);
    expect(appSettingsFromCacheJson(<int>[1]), isNull);
  });

  test('empty settings still serialize photoStripConfig', () {
    final json = appSettingsToCacheJson(AppSettingsModel());
    expect(json['photoStripConfig'], isA<Map<String, dynamic>>());
    expect(appSettingsFromCacheJson(json), isNotNull);
  });
}
