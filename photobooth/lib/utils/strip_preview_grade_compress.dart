import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Long-edge cap for Classic look-picker grade uploads.
///
/// Server grades at 1600; we send smaller thumbs so booth Wi‑Fi does not sit
/// ~15s uploading four full-res Canon plates before `preview-grade` starts.
const int kStripPreviewGradeUploadMaxEdge = 960;

const int kStripPreviewGradeUploadJpegQuality = 80;

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
          interpolation: img.Interpolation.linear,
        );
      } else {
        work = img.copyResize(
          decoded,
          height: maxEdge,
          interpolation: img.Interpolation.linear,
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
