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
