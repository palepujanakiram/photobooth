import '../models/app_settings_model.dart';

/// JSON used by [CatalogDiskCache] so settings survive a kiosk restart.
Map<String, dynamic> appSettingsToCacheJson(AppSettingsModel s) {
  return <String, dynamic>{
    if (s.id != null) 'id': s.id,
    if (s.accountId != null) 'accountId': s.accountId,
    if (s.maxRegenerations != null) 'maxRegenerations': s.maxRegenerations,
    if (s.freeRegenerations != null) 'freeRegenerations': s.freeRegenerations,
    if (s.regenerationPrice != null) 'regenerationPrice': s.regenerationPrice,
    if (s.regenerationApprovalRequired != null)
      'regenerationApprovalRequired': s.regenerationApprovalRequired,
    if (s.initialPrice != null) 'initialPrice': s.initialPrice,
    if (s.additionalPrintPrice != null)
      'additionalPrintPrice': s.additionalPrintPrice,
    if (s.printLayout != null) 'printLayout': s.printLayout,
    if (s.upscaleEnabled != null) 'upscaleEnabled': s.upscaleEnabled,
    if (s.upscaleScale != null) 'upscaleScale': s.upscaleScale,
    if (s.upscaleUseAI != null) 'upscaleUseAI': s.upscaleUseAI,
    if (s.compressionQuality != null) 'compressionQuality': s.compressionQuality,
    if (s.compressionMaxDimension != null)
      'compressionMaxDimension': s.compressionMaxDimension,
    if (s.showGenerationCommentary != null)
      'showGenerationCommentary': s.showGenerationCommentary,
    if (s.thermalSafeMode != null) 'thermalSafeMode': s.thermalSafeMode,
    if (s.defaultAiProvider != null) 'defaultAiProvider': s.defaultAiProvider,
    if (s.fallbackAiProvider != null) 'fallbackAiProvider': s.fallbackAiProvider,
    if (s.enableControlNet != null) 'enableControlNet': s.enableControlNet,
    if (s.enableInstantId != null) 'enableInstantId': s.enableInstantId,
    if (s.instantIdStrength != null) 'instantIdStrength': s.instantIdStrength,
    if (s.enableFluxKontext != null) 'enableFluxKontext': s.enableFluxKontext,
    if (s.activeLanguages != null) 'activeLanguages': s.activeLanguages,
    if (s.photoUploadAllowed != null) 'photoUploadAllowed': s.photoUploadAllowed,
    if (s.printerEnabled != null) 'printerEnabled': s.printerEnabled,
    if (s.printerHost != null) 'printerHost': s.printerHost,
    if (s.printerPort != null) 'printerPort': s.printerPort,
    if (s.printerPath != null) 'printerPath': s.printerPath,
    if (s.printerTransport != null) 'printerTransport': s.printerTransport,
    if (s.cameraEnabled != null) 'cameraEnabled': s.cameraEnabled,
    if (s.cameraConnectionMode != null)
      'cameraConnectionMode': s.cameraConnectionMode,
    if (s.cameraSidecarHost != null) 'cameraSidecarHost': s.cameraSidecarHost,
    if (s.cameraSidecarPort != null) 'cameraSidecarPort': s.cameraSidecarPort,
    if (s.cameraSidecarPath != null) 'cameraSidecarPath': s.cameraSidecarPath,
    if (s.cameraLivePreviewEnabled != null)
      'cameraLivePreviewEnabled': s.cameraLivePreviewEnabled,
    if (s.receiptPrinterEnabled != null)
      'receiptPrinterEnabled': s.receiptPrinterEnabled,
    if (s.receiptPrinterHost != null) 'receiptPrinterHost': s.receiptPrinterHost,
    if (s.receiptPrinterPort != null) 'receiptPrinterPort': s.receiptPrinterPort,
    if (s.wcmPlusEnabled != null) 'wcmPlusEnabled': s.wcmPlusEnabled,
    if (s.wcmPlusPath != null) 'wcmPlusPath': s.wcmPlusPath,
    if (s.parallelImageCount != null) 'parallelImageCount': s.parallelImageCount,
    if (s.targetFraming != null) 'targetFraming': s.targetFraming,
    if (s.showFramingGuide != null) 'showFramingGuide': s.showFramingGuide,
    if (s.paymentGatewayEnabled != null)
      'paymentGatewayEnabled': s.paymentGatewayEnabled,
    if (s.paymentGatewayEnvironment != null)
      'paymentGatewayEnvironment': s.paymentGatewayEnvironment,
    if (s.paymentCollectionTiming != null)
      'paymentCollectionTiming': s.paymentCollectionTiming,
    if (s.watermarkEnabled != null) 'watermarkEnabled': s.watermarkEnabled,
    if (s.exifStampEnabled != null) 'exifStampEnabled': s.exifStampEnabled,
    if (s.c2paSigningEnabled != null) 'c2paSigningEnabled': s.c2paSigningEnabled,
    'photoStripConfig': <String, dynamic>{
      if (s.enableOsdScrub != null) 'enableOsdScrub': s.enableOsdScrub,
      if (s.injectAfMarkers != null) 'injectAfMarkers': s.injectAfMarkers,
      if (s.enableSurpriseMeAi != null)
        'enableSurpriseMeAi': s.enableSurpriseMeAi,
    },
    if (s.createdAt != null) 'createdAt': s.createdAt!.toIso8601String(),
    if (s.updatedAt != null) 'updatedAt': s.updatedAt!.toIso8601String(),
  };
}

AppSettingsModel? appSettingsFromCacheJson(Object? raw) {
  if (raw is! Map) return null;
  return AppSettingsModel.fromJson(Map<String, dynamic>.from(raw));
}
