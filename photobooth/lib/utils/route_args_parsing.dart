import '../screens/photo_capture/photo_model.dart';
import '../screens/photo_generate/photo_generate_viewmodel.dart';

/// Shared route-argument parsing helpers (reduces cognitive complexity in [route_args.dart]).
PhotoModel? parseOptionalPhotoModel(Object? raw) {
  return switch (raw) {
    null => null,
    final PhotoModel p => p,
    _ => null,
  };
}

List<GeneratedImage>? parseGeneratedImageList(Object? rawList) {
  if (rawList is! List) return null;
  final generatedImages = <GeneratedImage>[];
  for (final e in rawList) {
    if (e is! GeneratedImage) return null;
    generatedImages.add(e);
  }
  if (generatedImages.isEmpty) return null;
  return generatedImages;
}

DateTime? parseOptionalDateTime(Object? raw) {
  if (raw is DateTime) return raw;
  if (raw == null) return null;
  return DateTime.tryParse(raw.toString());
}

List<String> parseStringIdList(Object? raw) {
  if (raw is! List) return <String>[];
  return raw.map((e) => e.toString()).toList();
}
