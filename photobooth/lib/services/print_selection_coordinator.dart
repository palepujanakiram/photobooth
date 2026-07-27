import '../screens/photo_generate/photo_generate_viewmodel.dart';

/// Holds Classic strip + AI photos across capture → theme → generate hops.
///
/// Seeded after strip compose; Explore more AI sets [awaitingExploreMoreReturn]
/// so BEHOLD continue merges new looks back into print selection.
class PrintSelectionCoordinator {
  PrintSelectionCoordinator._();
  static final PrintSelectionCoordinator instance =
      PrintSelectionCoordinator._();

  List<GeneratedImage> images = [];
  String? stripPrintSize;
  String? transformationRunId;
  bool fromClassicStrip = false;
  bool awaitingExploreMoreReturn = false;

  void seed({
    required List<GeneratedImage> seedImages,
    String? stripPrintSize,
    String? transformationRunId,
    bool fromClassicStrip = true,
  }) {
    images = List<GeneratedImage>.from(seedImages);
    this.stripPrintSize = stripPrintSize;
    this.transformationRunId = transformationRunId;
    this.fromClassicStrip = fromClassicStrip;
    awaitingExploreMoreReturn = false;
  }

  void markExploreMore() {
    awaitingExploreMoreReturn = true;
  }

  /// True when AI generate should return here instead of Result.
  bool get shouldReturnFromGenerate =>
      awaitingExploreMoreReturn && fromClassicStrip;

  void mergeAiImages(List<GeneratedImage> selected) {
    for (final img in selected) {
      final url = img.imageUrl.trim();
      if (url.isEmpty) continue;
      final exists = images.any((e) => e.imageUrl.trim() == url);
      if (!exists) {
        images.add(img.copyWith(isSelected: true));
      }
    }
    awaitingExploreMoreReturn = false;
  }

  void replaceImages(List<GeneratedImage> next) {
    images = List<GeneratedImage>.from(next);
  }

  void clear() {
    images = [];
    stripPrintSize = null;
    transformationRunId = null;
    fromClassicStrip = false;
    awaitingExploreMoreReturn = false;
  }
}
