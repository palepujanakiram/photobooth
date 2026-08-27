import 'dart:convert';
import 'dart:typed_data';

import '../utils/app_strings.dart';

/// Returns a `data:image/...;base64,...` substring when [url] is or embeds one.
String? extractInlineImageDataUrl(String url) {
  if (url.startsWith(AppStrings.dataImagePrefix)) {
    return url;
  }
  final embedded = url.indexOf(AppStrings.dataImagePrefix);
  if (embedded < 0) {
    return null;
  }
  return url.substring(embedded);
}

/// Decodes bytes from a data URL (`data:image/...;base64,...`).
Uint8List? decodeInlineImageDataUrl(String dataUrl) {
  final commaIndex = dataUrl.indexOf(',');
  if (commaIndex < 0 || commaIndex >= dataUrl.length - 1) {
    return null;
  }
  final payload = dataUrl.substring(commaIndex + 1);
  try {
    return base64Decode(payload);
  } catch (_) {
    return null;
  }
}

/// True when [url] should not be fetched over HTTP (inline or embedded data URL).
bool isInlineImageCacheUrl(String url) {
  return extractInlineImageDataUrl(url) != null;
}

const kCatalogImageCacheKindTheme = 'theme';
const kCatalogImageCacheKindFrame = 'frame';
const _kDefaultImageCacheExt = '.jpg';
const _kCatalogCacheTokenMaxLen = 80;

final _catalogCacheToken = RegExp(r'^[a-z0-9._-]+$');

String? sanitizeCatalogCacheToken(String? raw) {
  final trimmed = raw?.trim().toLowerCase() ?? '';
  if (trimmed.isEmpty || !_catalogCacheToken.hasMatch(trimmed)) return null;
  if (trimmed.length <= _kCatalogCacheTokenMaxLen) return trimmed;
  return trimmed.substring(0, _kCatalogCacheTokenMaxLen);
}

String? catalogCacheKeyForTheme(String? themeId) {
  final id = sanitizeCatalogCacheToken(themeId);
  if (id == null) return null;
  return '$kCatalogImageCacheKindTheme-$id';
}

String? catalogCacheKeyForFrame(String? frameId) {
  final id = sanitizeCatalogCacheToken(frameId);
  if (id == null) return null;
  return '$kCatalogImageCacheKindFrame-$id';
}

/// Filename stem: `theme-{id}` / `frame-{id}` when known, else a URL hash.
String catalogImageCacheFileStem({
  String? cacheKey,
  required String imageUrl,
}) {
  final fromId = sanitizeCatalogCacheToken(cacheKey);
  if (fromId != null) return fromId;
  return urlHashImageCacheStem(imageUrl);
}

String urlHashImageCacheStem(String imageUrl) {
  final uri = Uri.tryParse(imageUrl.trim());
  final normalized = uri != null && uri.hasScheme
      ? '${uri.scheme}://${uri.host}${uri.path}'
      : imageUrl.trim();
  final b64 = base64UrlEncode(utf8.encode(normalized)).replaceAll('=', '');
  final safeKey = b64.length <= 140
      ? b64
      : '${b64.substring(0, 70)}_${b64.substring(b64.length - 70)}';
  return '${normalized.length}_$safeKey';
}

String imageCacheFileExtension(String imageUrl) {
  final path = Uri.tryParse(imageUrl)?.path ?? imageUrl;
  final dot = path.lastIndexOf('.');
  final slash = path.lastIndexOf('/');
  if (dot <= slash || dot >= path.length - 1) return _kDefaultImageCacheExt;
  final ext = path.substring(dot).toLowerCase();
  if (!RegExp(r'^\.\w{1,4}$').hasMatch(ext)) return _kDefaultImageCacheExt;
  return ext;
}
