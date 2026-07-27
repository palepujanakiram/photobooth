import '../services/print_selection_coordinator.dart';
import 'constants.dart';

/// Count AI deliverables in [generatedImages], excluding the Classic strip URL.
int countNonStripGeneratedImages({
  required List<dynamic> generatedImages,
  String? stripCompositeUrl,
}) {
  final strip = stripCompositeUrl?.trim() ?? '';
  var n = 0;
  for (final entry in generatedImages) {
    if (entry is! String) continue;
    final url = entry.trim();
    if (url.isEmpty) continue;
    if (strip.isNotEmpty && url == strip) continue;
    n++;
  }
  return n;
}

/// Strip compose used to increment [attemptsUsed]; that must not consume AI slots.
///
/// When [attemptsUsed] is higher than the number of non-strip generated images,
/// the excess is treated as a Classic strip slot and ignored for AI budget.
int effectiveAiAttemptsUsed({
  required int attemptsUsed,
  required List<dynamic> generatedImages,
  String? stripCompositeUrl,
}) {
  if (attemptsUsed <= 0) return 0;
  final aiCount = countNonStripGeneratedImages(
    generatedImages: generatedImages,
    stripCompositeUrl: stripCompositeUrl,
  );
  return attemptsUsed > aiCount ? aiCount : attemptsUsed;
}

/// Prefer the strip URL held by the print-selection hub (Classic → Explore more).
String? stripCompositeUrlFromPrintSelection() {
  final coordinator = PrintSelectionCoordinator.instance;
  final stripSize = coordinator.stripPrintSize?.trim() ?? '';
  for (final image in coordinator.images) {
    final size = image.printSize?.trim() ?? '';
    if (size == AppConstants.kPrintSizeStripDual2x6) {
      return image.imageUrl.trim();
    }
    if (stripSize.isNotEmpty && size == stripSize) {
      return image.imageUrl.trim();
    }
  }
  return null;
}
