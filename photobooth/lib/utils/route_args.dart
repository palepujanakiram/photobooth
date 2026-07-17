import '../models/customer_contact_capture.dart';
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
    this.contact = CustomerContactCapture.empty,
  });

  static ResultArgs? tryParse(Object? args) {
    if (args is ResultArgs) return args;
    if (args is Map) {
      final generatedImages = parseGeneratedImageList(args['generatedImages']);
      if (generatedImages == null) return null;
      final originalPhoto = parseOptionalPhotoModel(args['originalPhoto']);
      if (args['originalPhoto'] != null && originalPhoto == null) return null;
      return ResultArgs(
        generatedImages: generatedImages,
        originalPhoto: originalPhoto,
        printOrientation: PrintOrientation.tryParse(
              args['printOrientation']?.toString(),
            ) ??
            PrintOrientation.portrait,
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
