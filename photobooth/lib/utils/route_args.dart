import '../screens/photo_capture/photo_model.dart';
import '../screens/theme_selection/theme_model.dart';
import '../screens/photo_generate/photo_generate_viewmodel.dart';

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
      final photo = args['photo'] as PhotoModel?;
      final addOneMore = args['addOneMoreStyle'] == true;
      final used = args['usedThemeIds'];
      final usedIds = used is List ? used.map((e) => e.toString()).toList() : <String>[];
      return ThemeSelectionArgs(photo: photo, addOneMoreStyle: addOneMore, usedThemeIds: usedIds);
    }
    return null;
  }
}

class GenerateArgs {
  final PhotoModel photo;
  final ThemeModel theme;

  const GenerateArgs({required this.photo, required this.theme});

  static GenerateArgs? tryParse(Object? args) {
    if (args is GenerateArgs) return args;
    if (args is Map) {
      final photo = args['photo'] as PhotoModel?;
      final theme = args['theme'] as ThemeModel?;
      if (photo == null || theme == null) return null;
      return GenerateArgs(photo: photo, theme: theme);
    }
    return null;
  }
}

class ResultArgs {
  final List<GeneratedImage> generatedImages;
  final PhotoModel? originalPhoto;
  final String? customerName;
  final String? customerPhone;
  final bool customerWhatsappOptIn;

  const ResultArgs({
    required this.generatedImages,
    this.originalPhoto,
    this.customerName,
    this.customerPhone,
    this.customerWhatsappOptIn = false,
  });

  static ResultArgs? tryParse(Object? args) {
    if (args is ResultArgs) return args;
    if (args is Map) {
      final generatedImages = args['generatedImages'] as List<GeneratedImage>?;
      final originalPhoto = args['originalPhoto'] as PhotoModel?;
      if (generatedImages == null || generatedImages.isEmpty) return null;
      final name = args['customerName']?.toString();
      final phone = args['customerPhone']?.toString();
      final wa = args['customerWhatsappOptIn'] == true;
      return ResultArgs(
        generatedImages: generatedImages,
        originalPhoto: originalPhoto,
        customerName: name,
        customerPhone: phone,
        customerWhatsappOptIn: wa,
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
      final url = args['shareUrl']?.toString();
      final longUrl = args['shareLongUrl']?.toString();
      final expiresRaw = args['shareExpiresAt'];
      DateTime? expiresAt;
      if (expiresRaw is DateTime) {
        expiresAt = expiresRaw;
      } else if (expiresRaw != null) {
        expiresAt = DateTime.tryParse(expiresRaw.toString());
      }
      return ThankYouArgs(
        shareUrl: url,
        shareLongUrl: longUrl,
        shareExpiresAt: expiresAt,
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
      final generatedImages = args['generatedImages'] as List<GeneratedImage>?;
      if (generatedImages == null || generatedImages.isEmpty) return null;
      final originalPhoto = args['originalPhoto'] as PhotoModel?;
      final vm = args['resultViewModel'];
      final url = args['shareUrl']?.toString();
      final longUrl = args['shareLongUrl']?.toString();
      final expiresRaw = args['shareExpiresAt'];
      DateTime? expiresAt;
      if (expiresRaw is DateTime) {
        expiresAt = expiresRaw;
      } else if (expiresRaw != null) {
        expiresAt = DateTime.tryParse(expiresRaw.toString());
      }
      final kioskUrl = args['kioskShareUrl']?.toString();
      final waQueued = args['whatsappQueued'] == true;
      final waOptIn = args['customerWhatsappOptIn'] == true;
      final phone = args['customerPhone']?.toString();
      final pdf = args['receiptPdfUrl']?.toString();
      return QrShareArgs(
        generatedImages: generatedImages,
        originalPhoto: originalPhoto,
        resultViewModel: vm,
        shareUrl: url,
        shareLongUrl: longUrl,
        shareExpiresAt: expiresAt,
        kioskShareUrl: kioskUrl,
        whatsappQueued: waQueued,
        customerWhatsappOptIn: waOptIn,
        customerPhone: phone,
        receiptPdfUrl: pdf,
      );
    }
    return null;
  }
}

