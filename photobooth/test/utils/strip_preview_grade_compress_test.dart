import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photobooth/utils/strip_preview_grade_compress.dart';

void main() {
  test('compresses tall stills down to grade upload max edge', () async {
    final big = img.Image(width: 1944, height: 2592);
    img.fill(big, color: img.ColorRgb8(40, 50, 60));
    final dataUrl =
        'data:image/jpeg;base64,${base64Encode(img.encodeJpg(big, quality: 90))}';

    final out = await compressDataUrlsForStripPreviewGrade([dataUrl]);
    expect(out, hasLength(1));

    final match = RegExp(r'^data:image/jpeg;base64,(.+)$').firstMatch(out.single);
    expect(match, isNotNull);
    final decoded = img.decodeImage(base64Decode(match!.group(1)!));
    expect(decoded, isNotNull);
    expect(
      decoded!.width >= decoded.height ? decoded.width : decoded.height,
      kStripPreviewGradeUploadMaxEdge,
    );
    expect(out.single.length, lessThan(dataUrl.length));
  });

  test('compresses landscape stills by width', () {
    final wide = img.Image(width: 2400, height: 1200);
    img.fill(wide, color: img.ColorRgb8(70, 80, 90));
    final dataUrl =
        'data:image/jpeg;base64,${base64Encode(img.encodeJpg(wide, quality: 90))}';
    final out = compressOneStripPreviewGradeDataUrlForTest(dataUrl);
    final match = RegExp(r'^data:image/jpeg;base64,(.+)$').firstMatch(out)!;
    final decoded = img.decodeImage(base64Decode(match.group(1)!))!;
    expect(decoded.width, kStripPreviewGradeUploadMaxEdge);
    expect(decoded.height, lessThan(kStripPreviewGradeUploadMaxEdge));
  });

  test('fail-open leaves invalid data URLs unchanged', () {
    const bad = 'data:image/jpeg;base64,not-a-real-image';
    expect(compressOneStripPreviewGradeDataUrlForTest(bad), bad);
  });

  test('returns empty list unchanged', () async {
    expect(await compressDataUrlsForStripPreviewGrade(const []), isEmpty);
  });

  test('pass-through non data URLs', () {
    expect(
      compressOneStripPreviewGradeDataUrlForTest('https://example.com/a.jpg'),
      'https://example.com/a.jpg',
    );
  });

  test('keeps already-small stills under max edge', () {
    final small = img.Image(width: 400, height: 300);
    img.fill(small, color: img.ColorRgb8(10, 20, 30));
    final dataUrl =
        'data:image/jpeg;base64,${base64Encode(img.encodeJpg(small, quality: 90))}';
    final out = compressOneStripPreviewGradeDataUrlForTest(dataUrl);
    final match = RegExp(r'^data:image/jpeg;base64,(.+)$').firstMatch(out)!;
    final decoded = img.decodeImage(base64Decode(match.group(1)!))!;
    expect(decoded.width, 400);
    expect(decoded.height, 300);
  });
}
