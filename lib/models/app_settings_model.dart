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
  final bool? showGenerationCommentary;
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
  final bool? wcmPlusEnabled;
  final String? wcmPlusPath;
  final int? parallelImageCount;
  final String? targetFraming;
  final bool? showFramingGuide;
  final bool? paymentGatewayEnabled;
  final String? paymentGatewayEnvironment;
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
    this.wcmPlusEnabled,
    this.wcmPlusPath,
    this.parallelImageCount,
    this.targetFraming,
    this.showFramingGuide,
    this.paymentGatewayEnabled,
    this.paymentGatewayEnvironment,
    this.watermarkEnabled,
    this.exifStampEnabled,
    this.c2paSigningEnabled,
    this.createdAt,
    this.updatedAt,
  });

  factory AppSettingsModel.fromJson(Map<String, dynamic> json) {
    return AppSettingsModel(
      id: json['id'] as String?,
      accountId: json['accountId'] as String?,
      maxRegenerations: json['maxRegenerations'] as int?,
      freeRegenerations: json['freeRegenerations'] as int?,
      regenerationPrice: json['regenerationPrice'] as int?,
      regenerationApprovalRequired:
          json['regenerationApprovalRequired'] as bool?,
      initialPrice: (json['initialPrice'] as num?)?.toInt(),
      additionalPrintPrice: (json['additionalPrintPrice'] as num?)?.toInt(),
      printLayout: json['printLayout'] as String?,
      upscaleEnabled: json['upscaleEnabled'] as bool?,
      upscaleScale: json['upscaleScale'] as int?,
      upscaleUseAI: json['upscaleUseAI'] as bool?,
      compressionQuality: json['compressionQuality'] as int?,
      compressionMaxDimension: json['compressionMaxDimension'] as int?,
      showGenerationCommentary: json['showGenerationCommentary'] as bool?,
      defaultAiProvider: json['defaultAiProvider'] as String?,
      fallbackAiProvider: json['fallbackAiProvider'] as String?,
      enableControlNet: json['enableControlNet'] as bool?,
      enableInstantId: json['enableInstantId'] as bool?,
      instantIdStrength: json['instantIdStrength'] as int?,
      enableFluxKontext: json['enableFluxKontext'] as bool?,
      activeLanguages: (json['activeLanguages'] as List<dynamic>?)
          ?.map((language) => language.toString())
          .toList(),
      photoUploadAllowed: json['photoUploadAllowed'] as bool?,
      printerEnabled: json['printerEnabled'] as bool?,
      printerHost: json['printerHost'] as String?,
      printerPort: (json['printerPort'] as num?)?.toInt(),
      wcmPlusEnabled: json['wcmPlusEnabled'] as bool?,
      wcmPlusPath: json['wcmPlusPath'] as String?,
      parallelImageCount: json['parallelImageCount'] as int?,
      targetFraming: json['targetFraming'] as String?,
      showFramingGuide: json['showFramingGuide'] as bool?,
      paymentGatewayEnabled: json['paymentGatewayEnabled'] as bool?,
      paymentGatewayEnvironment: json['paymentGatewayEnvironment'] as String?,
      watermarkEnabled: json['watermarkEnabled'] as bool?,
      exifStampEnabled: json['exifStampEnabled'] as bool?,
      c2paSigningEnabled: json['c2paSigningEnabled'] as bool?,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
    );
  }
}
