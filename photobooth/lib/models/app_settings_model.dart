import '../utils/json_parse_helpers.dart';

class AppSettingsModel {
  final String? id;
  final String? accountId;
  final int? maxRegenerations;
  final int? freeRegenerations;
  final int? regenerationPrice;
  final bool? regenerationApprovalRequired;
  final int? initialPrice;
  final int? additionalPrintPrice;
  final String? printLayout;
  final bool? upscaleEnabled;
  final int? upscaleScale;
  final bool? upscaleUseAI;
  final int? compressionQuality;
  final int? compressionMaxDimension;
  /// When true (from `/api/settings`), show generation commentary; also RAM monitor on capture.
  final bool? showGenerationCommentary;

  /// When true, enables UVC thermal relief (idle feed sleep, lifecycle pause) on capture.
  final bool? thermalSafeMode;
  final String? defaultAiProvider;
  final String? fallbackAiProvider;
  final bool? enableControlNet;
  final bool? enableInstantId;
  final int? instantIdStrength;
  final bool? enableFluxKontext;
  final List<String>? activeLanguages;
  final bool? photoUploadAllowed;
  final bool? printerEnabled;
  final String? printerHost;
  final int? printerPort;
  final String? printerPath;
  final bool? wcmPlusEnabled;
  final String? wcmPlusPath;
  final int? parallelImageCount;
  final String? targetFraming;
  final bool? showFramingGuide;
  final bool? paymentGatewayEnabled;
  final String? paymentGatewayEnvironment;
  /// `before_generation` | `after_generation` (default).
  final String? paymentCollectionTiming;
  final bool? watermarkEnabled;
  final bool? exifStampEnabled;
  final bool? c2paSigningEnabled;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  AppSettingsModel({
    this.id,
    this.accountId,
    this.maxRegenerations,
    this.freeRegenerations,
    this.regenerationPrice,
    this.regenerationApprovalRequired,
    this.initialPrice,
    this.additionalPrintPrice,
    this.printLayout,
    this.upscaleEnabled,
    this.upscaleScale,
    this.upscaleUseAI,
    this.compressionQuality,
    this.compressionMaxDimension,
    this.showGenerationCommentary,
    this.thermalSafeMode,
    this.defaultAiProvider,
    this.fallbackAiProvider,
    this.enableControlNet,
    this.enableInstantId,
    this.instantIdStrength,
    this.enableFluxKontext,
    this.activeLanguages,
    this.photoUploadAllowed,
    this.printerEnabled,
    this.printerHost,
    this.printerPort,
    this.printerPath,
    this.wcmPlusEnabled,
    this.wcmPlusPath,
    this.parallelImageCount,
    this.targetFraming,
    this.showFramingGuide,
    this.paymentGatewayEnabled,
    this.paymentGatewayEnvironment,
    this.paymentCollectionTiming,
    this.watermarkEnabled,
    this.exifStampEnabled,
    this.c2paSigningEnabled,
    this.createdAt,
    this.updatedAt,
  });

  factory AppSettingsModel.fromJson(Map<String, dynamic> json) {
    return AppSettingsModel(
      id: JsonParseHelpers.stringOrNull(json['id']),
      accountId: JsonParseHelpers.stringOrNull(json['accountId']),
      maxRegenerations: JsonParseHelpers.intOrNull(json['maxRegenerations']),
      freeRegenerations: JsonParseHelpers.intOrNull(json['freeRegenerations']),
      regenerationPrice: JsonParseHelpers.intOrNull(json['regenerationPrice']),
      regenerationApprovalRequired:
          JsonParseHelpers.boolOrNull(json['regenerationApprovalRequired']),
      initialPrice: JsonParseHelpers.intOrNull(json['initialPrice']),
      additionalPrintPrice:
          JsonParseHelpers.intOrNull(json['additionalPrintPrice']),
      printLayout: JsonParseHelpers.stringOrNull(json['printLayout']),
      upscaleEnabled: JsonParseHelpers.boolOrNull(json['upscaleEnabled']),
      upscaleScale: JsonParseHelpers.intOrNull(json['upscaleScale']),
      upscaleUseAI: JsonParseHelpers.boolOrNull(json['upscaleUseAI']),
      compressionQuality: JsonParseHelpers.intOrNull(json['compressionQuality']),
      compressionMaxDimension:
          JsonParseHelpers.intOrNull(json['compressionMaxDimension']),
      showGenerationCommentary:
          JsonParseHelpers.boolOrNull(json['showGenerationCommentary']),
      thermalSafeMode: JsonParseHelpers.boolOrNull(json['thermalSafeMode']),
      defaultAiProvider: JsonParseHelpers.stringOrNull(json['defaultAiProvider']),
      fallbackAiProvider:
          JsonParseHelpers.stringOrNull(json['fallbackAiProvider']),
      enableControlNet: JsonParseHelpers.boolOrNull(json['enableControlNet']),
      enableInstantId: JsonParseHelpers.boolOrNull(json['enableInstantId']),
      instantIdStrength: JsonParseHelpers.intOrNull(json['instantIdStrength']),
      enableFluxKontext: JsonParseHelpers.boolOrNull(json['enableFluxKontext']),
      activeLanguages: (json['activeLanguages'] as List<dynamic>?)
          ?.map((language) => language.toString())
          .toList(),
      photoUploadAllowed: JsonParseHelpers.boolOrNull(json['photoUploadAllowed']),
      printerEnabled: JsonParseHelpers.boolOrNull(json['printerEnabled']),
      printerHost: JsonParseHelpers.stringOrNull(json['printerHost']),
      printerPort: JsonParseHelpers.intOrNull(json['printerPort']),
      printerPath: JsonParseHelpers.stringOrNull(json['printerPath']),
      wcmPlusEnabled: JsonParseHelpers.boolOrNull(json['wcmPlusEnabled']),
      wcmPlusPath: JsonParseHelpers.stringOrNull(json['wcmPlusPath']),
      parallelImageCount: JsonParseHelpers.intOrNull(json['parallelImageCount']),
      targetFraming: JsonParseHelpers.stringOrNull(json['targetFraming']),
      showFramingGuide: JsonParseHelpers.boolOrNull(json['showFramingGuide']),
      paymentGatewayEnabled:
          JsonParseHelpers.boolOrNull(json['paymentGatewayEnabled']),
      paymentGatewayEnvironment:
          JsonParseHelpers.stringOrNull(json['paymentGatewayEnvironment']),
      paymentCollectionTiming:
          JsonParseHelpers.stringOrNull(json['paymentCollectionTiming']),
      watermarkEnabled: JsonParseHelpers.boolOrNull(json['watermarkEnabled']),
      exifStampEnabled: JsonParseHelpers.boolOrNull(json['exifStampEnabled']),
      c2paSigningEnabled: JsonParseHelpers.boolOrNull(json['c2paSigningEnabled']),
      createdAt: JsonParseHelpers.dateTimeOrNull(json['createdAt']),
      updatedAt: JsonParseHelpers.dateTimeOrNull(json['updatedAt']),
    );
  }
}
