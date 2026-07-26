import '../models/customer_contact_capture.dart';
import '../models/strip_models.dart';
import '../screens/photo_capture/photo_model.dart';
import '../screens/theme_selection/theme_model.dart';
import '../screens/photo_generate/photo_generate_viewmodel.dart';
import 'print_orientation.dart';
import 'route_args_parsing.dart';

class ThemeSelectionArgs {
  final PhotoModel? photo;
  final bool addOneMoreStyle;
  final List<String> usedThemeIds;

  const ThemeSelectionArgs({
    this.photo,
    this.addOneMoreStyle = false,
    this.usedThemeIds = const [],
  });

  static ThemeSelectionArgs? tryParse(Object? args) {
    if (args is ThemeSelectionArgs) return args;
    if (args is Map) {
      final photo = parseOptionalPhotoModel(args['photo']);
      if (args['photo'] != null && photo == null) return null;
      return ThemeSelectionArgs(
        photo: photo,
        addOneMoreStyle: args['addOneMoreStyle'] == true,
        usedThemeIds: parseStringIdList(args['usedThemeIds']),
      );
    }
    return null;
  }
}

/// Optional args for [AppConstants.kRouteCapture].
class CaptureRouteArgs {
  /// When true, Continue pops with [PhotoModel] (no session upload / theme nav).
  final bool returnPhotoOnly;

  /// Optional POSE subtitle override (e.g. "Shot 2 of 4").
  final String? subtitleHint;

  /// When set (e.g. 4), collect this many shots on the same POSE screen.
  final int? multiShotTotal;

  /// FotoFlashback theme — after [multiShotTotal] shots, open the look picker.
  final ThemeModel? flashbackTheme;

  /// Already-accepted FotoFlashback stills (restored after web camera remount).
  final List<PhotoModel> acceptedStripShots;

  const CaptureRouteArgs({
    this.returnPhotoOnly = false,
    this.subtitleHint,
    this.multiShotTotal,
    this.flashbackTheme,
    this.acceptedStripShots = const [],
  });

  bool get isFlashbackMultiShot =>
      returnPhotoOnly &&
      multiShotTotal != null &&
      multiShotTotal! > 1 &&
      flashbackTheme != null;

  static CaptureRouteArgs? tryParse(Object? args) {
    if (args is CaptureRouteArgs) return args;
    if (args is Map) {
      final totalRaw = args['multiShotTotal'];
      final total = totalRaw is int
          ? totalRaw
          : int.tryParse(totalRaw?.toString() ?? '');
      final rawShots = args['acceptedStripShots'];
      final shots = <PhotoModel>[];
      if (rawShots is List) {
        for (final item in rawShots) {
          if (item is PhotoModel) shots.add(item);
        }
      }
      return CaptureRouteArgs(
        returnPhotoOnly: args['returnPhotoOnly'] == true,
        subtitleHint: args['subtitleHint']?.toString(),
        multiShotTotal: total,
        flashbackTheme:
            args['flashbackTheme'] is ThemeModel
                ? args['flashbackTheme'] as ThemeModel
                : null,
        acceptedStripShots: shots,
      );
    }
    return null;
  }
}

/// Args for FotoFlashback 4-shot capture.
class FlashbackCaptureArgs {
  final ThemeModel theme;

  const FlashbackCaptureArgs({required this.theme});

  static FlashbackCaptureArgs? tryParse(Object? args) {
    if (args is FlashbackCaptureArgs) return args;
    if (args is Map && args['theme'] is ThemeModel) {
      return FlashbackCaptureArgs(theme: args['theme'] as ThemeModel);
    }
    return null;
  }
}

/// Args for FotoFlashback filter + compose.
class FlashbackFilterArgs {
  final ThemeModel theme;
  final List<String> imageDataUrls;

  const FlashbackFilterArgs({
    required this.theme,
    required this.imageDataUrls,
  });

  static FlashbackFilterArgs? tryParse(Object? args) {
    if (args is FlashbackFilterArgs) return args;
    if (args is Map && args['theme'] is ThemeModel) {
      final raw = args['imageDataUrls'] ?? args['images'];
      if (raw is! List) return null;
      final urls = raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
      return FlashbackFilterArgs(
        theme: args['theme'] as ThemeModel,
        imageDataUrls: urls,
      );
    }
    return null;
  }
}

/// Pre-payment before strip compose (same timing setting as AI generation).
class FlashbackPrePayArgs {
  final ThemeModel theme;
  final List<String> imageDataUrls;
  final String filterId;

  const FlashbackPrePayArgs({
    required this.theme,
    required this.imageDataUrls,
    required this.filterId,
  });

  static FlashbackPrePayArgs? tryParse(Object? args) {
    if (args is FlashbackPrePayArgs) return args;
    if (args is Map &&
        args['theme'] is ThemeModel &&
        args['filterId'] is String) {
      final raw = args['imageDataUrls'] ?? args['images'];
      if (raw is! List) return null;
      final urls =
          raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
      if (urls.length != kStripShotCount) return null;
      return FlashbackPrePayArgs(
        theme: args['theme'] as ThemeModel,
        imageDataUrls: urls,
        filterId: args['filterId'] as String,
      );
    }
    return null;
  }
}

class GenerateArgs {
  final PhotoModel photo;
  final ThemeModel theme;

  /// Unique per navigation so `/generate-progress` can restart when re-entered.
  final int runToken;

  GenerateArgs({
    required this.photo,
    required this.theme,
    int? runToken,
  }) : runToken = runToken ?? DateTime.now().microsecondsSinceEpoch;

  static GenerateArgs? tryParse(Object? args) {
    if (args is GenerateArgs) return args;
    if (args is Map) {
      final p = args['photo'];
      final t = args['theme'];
      if (p is! PhotoModel || t is! ThemeModel) return null;
      final token = args['runToken'];
      return GenerateArgs(
        photo: p,
        theme: t,
        runToken: token is int ? token : Object.hash(p.id, t.id),
      );
    }
    return null;
  }
}

class ResultArgs {
  final List<GeneratedImage> generatedImages;
  final PhotoModel? originalPhoto;
  final PrintOrientation printOrientation;

  /// FotoFlashback only — WCM cut size (e.g. `s6x2_2` for `6x2*2`). Null keeps AI size.
  final String? printSize;

  /// Transformation run for View details (FotoFlashback compose / AI generate).
  final String? transformationRunId;
  final CustomerContactCapture contact;

  String? get customerName =>
      contact.customerName.isEmpty ? null : contact.customerName;
  String? get customerPhone =>
      contact.customerPhone.isEmpty ? null : contact.customerPhone;
  bool get customerWhatsappOptIn => contact.whatsappOptIn;

  const ResultArgs({
    required this.generatedImages,
    this.originalPhoto,
    this.printOrientation = PrintOrientation.portrait,
    this.printSize,
    this.transformationRunId,
    this.contact = CustomerContactCapture.empty,
  });

  static ResultArgs? tryParse(Object? args) {
    if (args is ResultArgs) return args;
    if (args is Map) {
      final generatedImages = parseGeneratedImageList(args['generatedImages']);
      if (generatedImages == null) return null;
      final originalPhoto = parseOptionalPhotoModel(args['originalPhoto']);
      if (args['originalPhoto'] != null && originalPhoto == null) return null;
      final rawPrintSize = args['printSize']?.toString().trim();
      final rawRunId = args['transformationRunId']?.toString().trim() ??
          args['runId']?.toString().trim();
      return ResultArgs(
        generatedImages: generatedImages,
        originalPhoto: originalPhoto,
        printOrientation: PrintOrientation.tryParse(
              args['printOrientation']?.toString(),
            ) ??
            PrintOrientation.portrait,
        printSize: (rawPrintSize != null && rawPrintSize.isNotEmpty)
            ? rawPrintSize
            : null,
        transformationRunId:
            (rawRunId != null && rawRunId.isNotEmpty) ? rawRunId : null,
        contact: CustomerContactCapture.tryParseRouteMap(args),
      );
    }
    return null;
  }
}

class ThankYouArgs {
  final String? shareUrl;
  final String? shareLongUrl;
  final DateTime? shareExpiresAt;

  const ThankYouArgs({
    this.shareUrl,
    this.shareLongUrl,
    this.shareExpiresAt,
  });

  static ThankYouArgs? tryParse(Object? args) {
    if (args is ThankYouArgs) return args;
    if (args is Map) {
      return ThankYouArgs(
        shareUrl: args['shareUrl']?.toString(),
        shareLongUrl: args['shareLongUrl']?.toString(),
        shareExpiresAt: parseOptionalDateTime(args['shareExpiresAt']),
      );
    }
    return null;
  }
}

class QrShareArgs {
  final List<GeneratedImage> generatedImages;
  final PhotoModel? originalPhoto;

  /// Optional [ResultViewModel] from Pay & Collect (not JSON-serializable).
  final Object? resultViewModel;
  final String? shareUrl;
  final String? shareLongUrl;
  final DateTime? shareExpiresAt;
  final String? kioskShareUrl;
  final bool whatsappQueued;
  final bool customerWhatsappOptIn;
  final String? customerPhone;
  final String? receiptPdfUrl;

  const QrShareArgs({
    required this.generatedImages,
    this.originalPhoto,
    this.resultViewModel,
    this.shareUrl,
    this.shareLongUrl,
    this.shareExpiresAt,
    this.kioskShareUrl,
    this.whatsappQueued = false,
    this.customerWhatsappOptIn = false,
    this.customerPhone,
    this.receiptPdfUrl,
  });

  static QrShareArgs? tryParse(Object? args) {
    if (args is QrShareArgs) return args;
    if (args is Map) {
      final generatedImages = parseGeneratedImageList(args['generatedImages']);
      if (generatedImages == null) return null;
      final originalPhoto = parseOptionalPhotoModel(args['originalPhoto']);
      if (args['originalPhoto'] != null && originalPhoto == null) return null;
      return QrShareArgs(
        generatedImages: generatedImages,
        originalPhoto: originalPhoto,
        resultViewModel: args['resultViewModel'],
        shareUrl: args['shareUrl']?.toString(),
        shareLongUrl: args['shareLongUrl']?.toString(),
        shareExpiresAt: parseOptionalDateTime(args['shareExpiresAt']),
        kioskShareUrl: args['kioskShareUrl']?.toString(),
        whatsappQueued: args['whatsappQueued'] == true,
        customerWhatsappOptIn: args['customerWhatsappOptIn'] == true,
        customerPhone: args['customerPhone']?.toString(),
        receiptPdfUrl: args['receiptPdfUrl']?.toString(),
      );
    }
    return null;
  }
}
