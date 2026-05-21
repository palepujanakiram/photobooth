/// Centralized user-visible and diagnostic strings.
///
/// Keeps copy consistent across screens and satisfies Sonar rule S1192
/// (duplicated string literals). Do not put secrets here — values are shipped
/// in the client binary.
abstract final class AppStrings {
  /// Shown after a successful silent print to the network printer.
  static const printJobSentSuccess = 'Print job sent successfully!';

  /// Browser / Dio message when a web request cannot reach the API (CORS, offline).
  static const failedToFetch = 'Failed to fetch';

  /// Fallback when [DioException.message] is empty on network failures.
  static const unknownNetworkError = 'Unknown network error';

  /// Thrown when a captured or downloaded image file has zero bytes.
  static const imageFileEmpty = 'Image file is empty';

  /// Debug log label for USB/external cameras in [CaptureViewModel].
  static const cameraLabelExternal = '[external]';

  /// Debug log label for built-in cameras in [CaptureViewModel].
  static const cameraLabelBuiltIn = '[built-in]';

  /// Stack-frame filter: skip internal frames from [AppLogger] when parsing callers.
  static const loggerFileName = 'logger.dart';

  /// Horizontal rule in API request/response debug logs (mobile + web formatters).
  static const apiLogSeparator = '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
}
