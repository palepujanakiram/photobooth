import 'app_config.dart';

/// Resolves a theme [sampleImageUrl] from the API to an absolute HTTP(S) URL.
///
/// Relative paths are joined with [AppConfig.baseUrl] the same way as
/// [ThemeSlideshowViewModel.getSampleImageUrls] and [ThemeCard], so slideshow,
/// theme picker, and review screens all show the same image address.
String resolveThemeSampleImageUrl(String imageUrl) {
  final trimmed = imageUrl.trim();
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  final baseUrl = AppConfig.baseUrl.endsWith('/')
      ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
      : AppConfig.baseUrl;
  final relativePath = trimmed.startsWith('/') ? trimmed : '/$trimmed';
  return '$baseUrl$relativePath';
}

/// Normalizes a URL for theme ↔ slideshow image matching (drops query and fragment).
///
/// Used when comparing the current slideshow frame URL to each theme's sample URL.
String normalizeThemeImageUrl(String url) {
  try {
    final uri = Uri.parse(url);
    return '${uri.scheme}://${uri.host}${uri.path}';
  } catch (_) {
    return url;
  }
}

/// Returns true when [url] can be parsed as a URI (used before caching network images).
bool isValidHttpUrl(String url) {
  try {
    Uri.parse(url);
    return true;
  } catch (_) {
    return false;
  }
}
