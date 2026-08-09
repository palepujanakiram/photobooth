import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photobooth/models/strip_models.dart';
import 'package:photobooth/utils/strip_look_color_matrices.dart';
import 'package:photobooth/utils/strip_look_matrix_bake.dart';

void main() {
  group('stripLookColorMatrixValues', () {
    test('covers catalog ids and unknown falls back to identity', () {
      for (final id in kStripFilterIds) {
        expect(stripLookColorMatrixValues(id), hasLength(20), reason: id);
      }
      expect(stripLookColorMatrixValues('unknown'), hasLength(20));
      expect(stripLookNeedsMatrixBake('clean'), isFalse);
      expect(stripLookNeedsMatrixBake('classic_warm'), isTrue);
      expect(stripLookNeedsMatrixBake(''), isFalse);
      expect(kStripComposePreBakedFilterId, 'clean');
    });
  });

  group('bakeStripLookMatricesOntoDataUrls', () {
    test('mono bakes luminance into JPEG pixels', () async {
      final src = img.Image(width: 8, height: 8);
      img.fill(src, color: img.ColorRgb8(255, 0, 0));
      final dataUrl =
          'data:image/jpeg;base64,${base64Encode(img.encodeJpg(src, quality: 95))}';

      final out = await bakeStripLookMatricesOntoDataUrls(
        dataUrls: [dataUrl],
        filterId: 'mono',
      );
      expect(out, hasLength(1));
      expect(out.single, isNot(dataUrl));

      final match =
          RegExp(r'^data:image/jpeg;base64,(.+)$').firstMatch(out.single)!;
      final decoded = img.decodeImage(base64Decode(match.group(1)!))!;
      final p = decoded.getPixel(0, 0);
      expect(p.r, closeTo(p.g, 8));
      expect(p.g, closeTo(p.b, 8));
    });

    test('downscales tall plates to print bake max edge', () {
      final big = img.Image(width: 1944, height: 2592);
      img.fill(big, color: img.ColorRgb8(40, 50, 60));
      final dataUrl =
          'data:image/jpeg;base64,${base64Encode(img.encodeJpg(big, quality: 90))}';
      final out = bakeOneStripLookMatrixDataUrlForTest(
        dataUrl,
        stripLookColorMatrixValues('classic_warm'),
      );
      final match =
          RegExp(r'^data:image/jpeg;base64,(.+)$').firstMatch(out)!;
      final decoded = img.decodeImage(base64Decode(match.group(1)!))!;
      final long =
          decoded.width >= decoded.height ? decoded.width : decoded.height;
      expect(long, kStripLookBakeMaxEdge);
    });

    test('clean is a no-op matrix but still fail-opens invalid URLs', () async {
      const raw = 'data:image/jpeg;base64,not-valid';
      final clean = await bakeStripLookMatricesOntoDataUrls(
        dataUrls: [raw],
        filterId: 'clean',
      );
      expect(clean.single, raw);

      expect(
        bakeOneStripLookMatrixDataUrlForTest(
          raw,
          stripLookColorMatrixValues('classic_warm'),
        ),
        raw,
      );
      expect(
        bakeOneStripLookMatrixDataUrlForTest('not-a-data-url', null),
        'not-a-data-url',
      );
      expect(
        bakeOneStripLookMatrixDataUrlForTest(raw, const <double>[1]),
        raw,
      );
    });

    test('classic_warm lifts red and softens blue on a cool patch', () {
      final src = img.Image(width: 6, height: 6);
      img.fill(src, color: img.ColorRgb8(40, 60, 180));
      final dataUrl =
          'data:image/jpeg;base64,${base64Encode(img.encodeJpg(src, quality: 95))}';
      final out = bakeOneStripLookMatrixDataUrlForTest(
        dataUrl,
        stripLookColorMatrixValues('classic_warm'),
      );
      final match =
          RegExp(r'^data:image/jpeg;base64,(.+)$').firstMatch(out)!;
      final decoded = img.decodeImage(base64Decode(match.group(1)!))!;
      final p = decoded.getPixel(2, 2);
      expect(p.r, greaterThan(45));
      expect(p.b, lessThan(170));
      expect(p.r / p.b, greaterThan(40 / 180));
    });
  });
}
