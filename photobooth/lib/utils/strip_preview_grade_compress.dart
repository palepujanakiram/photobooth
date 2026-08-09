import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Long-edge cap for Classic look-picker grade uploads.
///
/// Server grades around 1600; we used to send 960/q80 thumbs for Wi‑Fi speed,
/// which made "Pick your look" look soft vs the DSLR plate. 1600/q90 stays
/// under full Canon size while matching on-screen tablet strip cells.
const int kStripPreviewGradeUploadMaxEdge = 1600;

const int kStripPreviewGradeUploadJpegQuality = 90;

/// Downscale strip shot data URLs before POST `/strip/preview-grade`.
///
/// Fail-open: on decode errors returns the original URL for that slot.
Future<List<String>> compressDataUrlsForStripPreviewGrade(
  List<String> dataUrls,
) async {
  if (dataUrls.isEmpty) return dataUrls;
  return compute(_compressStripPreviewGradeIsolate, List<String>.from(dataUrls));
}

List<String> _compressStripPreviewGradeIsolate(List<String> dataUrls) {
  return [for (final url in dataUrls) _compressOneStripPreviewGradeDataUrl(url)];
}

@visibleForTesting
String compressOneStripPreviewGradeDataUrlForTest(String dataUrl) =>
    _compressOneStripPreviewGradeDataUrl(dataUrl);

String _compressOneStripPreviewGradeDataUrl(String dataUrl) {
  final trimmed = dataUrl.trim();
  final match = RegExp(r'^data:([^;]+);base64,(.+)$').firstMatch(trimmed);
  if (match == null) return dataUrl;

  try {
    final bytes = base64Decode(match.group(2)!);
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return dataUrl;

    const maxEdge = kStripPreviewGradeUploadMaxEdge;
    img.Image work = decoded;
    final longEdge =
        decoded.width >= decoded.height ? decoded.width : decoded.height;
    if (longEdge > maxEdge) {
      if (decoded.width >= decoded.height) {
        work = img.copyResize(
          decoded,
          width: maxEdge,
          interpolation: img.Interpolation.average,
        );
      } else {
        work = img.copyResize(
          decoded,
          height: maxEdge,
          interpolation: img.Interpolation.average,
        );
      }
    }

    final encoded = img.encodeJpg(
      work,
      quality: kStripPreviewGradeUploadJpegQuality,
    );
    return 'data:image/jpeg;base64,${base64Encode(encoded)}';
  } catch (_) {
    return dataUrl;
  }
}
