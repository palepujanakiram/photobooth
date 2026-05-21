import '../../utils/logger.dart';
import 'theme_slideshow_viewmodel.dart';

/// Returns false when the slideshow timer should stop (Sonar S3776 extraction).
bool themeSlideshowShouldAdvanceTick({
  required ThemeSlideshowViewModel viewModel,
  required List<String> imageUrls,
}) {
  if (!viewModel.areAllImagesLoaded) return false;
  return imageUrls.isNotEmpty;
}

/// Computes next slideshow index or null when tick should abort.
int? themeSlideshowNextIndex({
  required int currentIndex,
  required List<String> imageUrls,
}) {
  if (imageUrls.isEmpty) return null;
  return (currentIndex + 1) % imageUrls.length;
}

void themeSlideshowLogTimerError(Object e) {
  AppLogger.debug('Error in slideshow timer: $e');
}
