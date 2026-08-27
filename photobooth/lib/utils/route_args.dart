import '../models/customer_contact_capture.dart';
import '../models/strip_models.dart';
import '../screens/photo_capture/photo_model.dart';
import '../screens/theme_selection/theme_model.dart';
import '../screens/photo_generate/photo_generate_viewmodel.dart';
import 'classic_shot_mode.dart';
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

  /// Explicit Classic shot mode (survives Map round-trips better than total alone).
  final ClassicShotMode? classicShotMode;

  /// When true, show live POSE but do not auto-start the countdown (Back from looks).
  final bool awaitGuestStart;

  const CaptureRouteArgs({
    this.returnPhotoOnly = false,
    this.subtitleHint,
    this.multiShotTotal,
    this.flashbackTheme,
    this.acceptedStripShots = const [],
    this.classicShotMode,
    this.awaitGuestStart = false,
  });

  bool get isFlashbackMultiShot =>
      returnPhotoOnly &&
      multiShotTotal != null &&
      multiShotTotal! >= 1 &&
      flashbackTheme != null;

  /// Four-pose strip (look picker) vs single 6×4 print.
  bool get isFlashbackFourShot =>
      isFlashbackMultiShot && resolvedShotTotal > 1;

  bool get isFlashbackSingle6x4 =>
      isFlashbackMultiShot && resolvedShotTotal == 1;

  /// Prefer [classicShotMode] when present so 1-shot cannot become 4.
  int get resolvedShotTotal {
    final mode = classicShotMode;
    if (mode != null) return mode.shotCount;
    return multiShotTotal ?? 0;
  }

  static CaptureRouteArgs? tryParse(Object? args) {
    if (args is CaptureRouteArgs) return args;
    if (args is Map) {
      final mode = _parseClassicShotMode(args['classicShotMode']);
      final totalRaw = args['multiShotTotal'];
      var total = totalRaw is int
          ? totalRaw
          : int.tryParse(totalRaw?.toString() ?? '');
      if (mode != null) {
        total = mode.shotCount;
      }
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
        classicShotMode: mode,
        awaitGuestStart: args['awaitGuestStart'] == true,
      );
    }
    return null;
  }

  static ClassicShotMode? _parseClassicShotMode(Object? raw) {
    if (raw is ClassicShotMode) return raw;
    final name = raw?.toString();
    if (name == null || name.isEmpty) return null;
    for (final mode in ClassicShotMode.values) {
      if (mode.name == name) return mode;
    }
    if (name == '1' || name == 'single' || name == 'single6x4') {
      return ClassicShotMode.single6x4;
    }
    if (name == '3' || name == 'three' || name == 'threeShot') {
      return ClassicShotMode.threeShot;
    }
    if (name == '4' || name == 'four' || name == 'fourShot') {
      return ClassicShotMode.fourShot;
    }
    return null;
  }
}

/// Parses [ClassicShotMode] from route maps / JSON-ish values.
ClassicShotMode? parseClassicShotModeArg(Object? raw) =>
    CaptureRouteArgs._parseClassicShotMode(raw);

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

/// Args for Classic shot-mode preview (after experience choice when >1 mode).
class ClassicShotChoiceArgs {
  final ThemeModel theme;
  final List<int> modes;

  const ClassicShotChoiceArgs({
    required this.theme,
    required this.modes,
  });

  static ClassicShotChoiceArgs? tryParse(Object? args) {
    if (args is ClassicShotChoiceArgs) return args;
    if (args is Map && args['theme'] is ThemeModel) {
      final raw = args['modes'];
      final modes = raw is List
          ? raw
              .map((e) => e is int ? e : int.tryParse('$e'))
              .whereType<int>()
              .toList()
          : const <int>[];
      return ClassicShotChoiceArgs(
        theme: args['theme'] as ThemeModel,
        modes: normalizeClassicShotModes(modes),
      );
    }
    return null;
  }
}

/// Args for FotoFlashback filter + compose.
class FlashbackFilterArgs {
  final ThemeModel theme;
  final List<String> imageDataUrls;

  /// JPEG paths to encode after the look screen is visible (direct PTP classic).
  ///
  /// When set, [imageDataUrls] may be empty on entry — avoids blocking navigation
  /// on base64 while the guest waits on a spinner.
  final List<String>? pendingImageFilePaths;

  /// True when capture already awaited per-shot Gemini scrub.
  final bool overlayCleanupAlreadyDone;
  /// Per-shot scrub success from capture (parallel to [imageDataUrls]).
  final List<bool> shotCleaned;
  /// Classic shot mode for Back → POSE (prefer over inferring from URL count).
  final ClassicShotMode? classicShotMode;

  /// Bumps when a new capture opens the look screen — avoids stale preview widgets.
  final int? previewSessionKey;

  const FlashbackFilterArgs({
    required this.theme,
    required this.imageDataUrls,
    this.pendingImageFilePaths,
    this.overlayCleanupAlreadyDone = false,
    this.shotCleaned = const [],
    this.classicShotMode,
    this.previewSessionKey,
  });

  int get _captureCount =>
      pendingImageFilePaths?.length ?? imageDataUrls.length;

  /// Mode used when returning from looks to Classic capture.
  ClassicShotMode get resolvedShotMode {
    final mode = classicShotMode;
    if (mode != null) return mode;
    return _captureCount == 1
        ? ClassicShotMode.single6x4
        : ClassicShotMode.fourShot;
  }

  static FlashbackFilterArgs? tryParse(Object? args) {
    if (args is FlashbackFilterArgs) return args;
    if (args is Map && args['theme'] is ThemeModel) {
      final raw = args['imageDataUrls'] ?? args['images'];
      final pendingRaw = args['pendingImageFilePaths'];
      final pending = pendingRaw is List
          ? pendingRaw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
          : null;
      if (raw is! List && (pending == null || pending.isEmpty)) return null;
      final urls = raw is List
          ? raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
          : const <String>[];
      final cleanedRaw = args['shotCleaned'];
      final shotCleaned = cleanedRaw is List
          ? cleanedRaw.map((e) => e == true).toList()
          : const <bool>[];
      return FlashbackFilterArgs(
        theme: args['theme'] as ThemeModel,
        imageDataUrls: urls,
        pendingImageFilePaths: pending?.isEmpty == true ? null : pending,
        overlayCleanupAlreadyDone: args['overlayCleanupAlreadyDone'] == true,
        shotCleaned: shotCleaned,
        classicShotMode: parseClassicShotModeArg(args['classicShotMode']),
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
      if (urls.length != 1 && urls.length != kStripShotCount) return null;
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

/// Args for the Classic + AI print selection hub.
class PrintSelectionArgs {
  final List<GeneratedImage> generatedImages;
  final String? stripPrintSize;
  final String? transformationRunId;

  /// When true, Back returns to Pick your look so guests can change the compose.
  final bool canEditLook;

  const PrintSelectionArgs({
    required this.generatedImages,
    this.stripPrintSize,
    this.transformationRunId,
    this.canEditLook = false,
  });

  static PrintSelectionArgs? tryParse(Object? args) {
    if (args is PrintSelectionArgs) return args;
    if (args is Map) {
      final generatedImages = parseGeneratedImageList(args['generatedImages']);
      if (generatedImages == null || generatedImages.isEmpty) return null;
      final rawPrintSize = args['stripPrintSize']?.toString().trim() ??
          args['printSize']?.toString().trim();
      final rawRunId = args['transformationRunId']?.toString().trim() ??
          args['runId']?.toString().trim();
      return PrintSelectionArgs(
        generatedImages: generatedImages,
        stripPrintSize: (rawPrintSize != null && rawPrintSize.isNotEmpty)
            ? rawPrintSize
            : null,
        transformationRunId:
            (rawRunId != null && rawRunId.isNotEmpty) ? rawRunId : null,
        canEditLook: args['canEditLook'] == true,
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
