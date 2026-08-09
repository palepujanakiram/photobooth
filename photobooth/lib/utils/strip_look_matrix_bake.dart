import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'strip_look_color_matrices.dart';

/// JPEG quality for look-baked compose uploads (print path).
const int kStripLookBakeJpegQuality = 95;

class _StripLookBakeArgs {
  const _StripLookBakeArgs({
    required this.dataUrls,
    required this.filterId,
  });

  final List<String> dataUrls;
  final String filterId;
}

/// Bakes Flutter look ColorFilter matrices into JPEG data URLs so compose /
/// print matches the look picker (server Sharp grades are skipped via
/// [kStripComposePreBakedFilterId]).
///
/// Fail-open: undecodable slots keep the original URL.
Future<List<String>> bakeStripLookMatricesOntoDataUrls({
  required List<String> dataUrls,
  required String filterId,
}) async {
  if (dataUrls.isEmpty || !stripLookNeedsMatrixBake(filterId)) {
    return List<String>.from(dataUrls);
  }
  return compute(
    _bakeStripLookMatricesIsolate,
    _StripLookBakeArgs(
      dataUrls: List<String>.from(dataUrls),
      filterId: filterId,
    ),
  );
}

List<String> _bakeStripLookMatricesIsolate(_StripLookBakeArgs args) {
  final matrix = stripLookColorMatrixValues(args.filterId);
  return [
    for (final url in args.dataUrls)
      bakeOneStripLookMatrixDataUrlForTest(url, matrix),
  ];
}

@visibleForTesting
String bakeOneStripLookMatrixDataUrlForTest(
  String dataUrl,
  List<double> matrix,
) {
  final trimmed = dataUrl.trim();
  final match = RegExp(r'^data:([^;]+);base64,(.+)$').firstMatch(trimmed);
  if (match == null) return dataUrl;
  if (matrix.length < 20) return dataUrl;

  try {
    final bytes = base64Decode(match.group(2)!);
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return dataUrl;

    final work = decoded.convert(numChannels: 4);
    _applyColorMatrixInPlace(work, matrix);
    final encoded = img.encodeJpg(work, quality: kStripLookBakeJpegQuality);
    return 'data:image/jpeg;base64,${base64Encode(encoded)}';
  } catch (_) {
    return dataUrl;
  }
}

void _applyColorMatrixInPlace(img.Image image, List<double> m) {
  for (final p in image) {
    final r = p.r.toDouble();
    final g = p.g.toDouble();
    final b = p.b.toDouble();
    final a = p.a.toDouble();
    final nr = r * m[0] + g * m[1] + b * m[2] + a * m[3] + m[4];
    final ng = r * m[5] + g * m[6] + b * m[7] + a * m[8] + m[9];
    final nb = r * m[10] + g * m[11] + b * m[12] + a * m[13] + m[14];
    final na = r * m[15] + g * m[16] + b * m[17] + a * m[18] + m[19];
    p
      ..r = nr.round().clamp(0, 255)
      ..g = ng.round().clamp(0, 255)
      ..b = nb.round().clamp(0, 255)
      ..a = na.round().clamp(0, 255);
  }
}
