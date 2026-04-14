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

  const ResultArgs({required this.generatedImages, this.originalPhoto});

  static ResultArgs? tryParse(Object? args) {
    if (args is ResultArgs) return args;
    if (args is Map) {
      final generatedImages = args['generatedImages'] as List<GeneratedImage>?;
      final originalPhoto = args['originalPhoto'] as PhotoModel?;
      if (generatedImages == null || generatedImages.isEmpty) return null;
      return ResultArgs(generatedImages: generatedImages, originalPhoto: originalPhoto);
    }
    return null;
  }
}

