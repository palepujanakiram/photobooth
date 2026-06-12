import '../../models/preprocess_image_result.dart';
import '../../utils/theme_filter.dart';

/// Resolves person count after upload preprocess (or when it fails/times out).
int resolvePersonCountAfterPreprocess({
  PreprocessImageResult? preprocess,
  required int clientFaceCount,
  int? sessionPersonCount,
}) {
  final fromPreprocess = preprocess?.personCount;
  if (fromPreprocess != null && fromPreprocess > 0) return fromPreprocess;
  if (sessionPersonCount != null && sessionPersonCount > 0) {
    return sessionPersonCount;
  }
  if (clientFaceCount > 0) return clientFaceCount;
  return ThemeFilter.effectivePersonCount(null);
}

/// Whether preprocess explicitly failed with no usable person count signals.
bool isHardPreprocessFailure({
  required PreprocessImageResult preprocess,
  required int clientFaceCount,
  int? sessionPersonCount,
}) {
  if (preprocess.success) return false;
  if (preprocess.personCount != null && preprocess.personCount! > 0) {
    return false;
  }
  if (clientFaceCount > 0) return false;
  if (sessionPersonCount != null && sessionPersonCount > 0) return false;
  return true;
}
