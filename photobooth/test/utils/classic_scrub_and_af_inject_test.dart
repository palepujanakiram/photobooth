import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photobooth/utils/classic_af_marker_inject.dart';
import 'package:photobooth/utils/classic_strip_scrub_helpers.dart';

void main() {
  group('classicOverlayScrubEnabled', () {
    test('defaults ON when admin flag is null', () {
      expect(classicOverlayScrubEnabled(null), isTrue);
    });

    test('respects explicit OFF', () {
      expect(classicOverlayScrubEnabled(false), isFalse);
    });

    test('respects explicit ON', () {
      expect(classicOverlayScrubEnabled(true), isTrue);
    });
  });

  group('scrubClassicShotDataUrl', () {
    test('returns raw encode when scrub disabled', () async {
      final out = await scrubClassicShotDataUrl(
        encodeShotDataUrl: () async => 'data:image/jpeg;base64,raw',
        enableScrub: false,
      );
      expect(out.dataUrl, 'data:image/jpeg;base64,raw');
      expect(out.scrubbed, isFalse);
    });
  });

  group('injectClassicAfMarkers', () {
    test('burns white AF brackets into a still', () async {
      final canvas = img.Image(width: 200, height: 280);
      img.fill(canvas, color: img.ColorRgb8(40, 40, 40));
      final bytes = Uint8List.fromList(img.encodeJpg(canvas, quality: 90));
      final source = XFile.fromData(
        bytes,
        mimeType: 'image/jpeg',
        name: 'plain.jpg',
      );

      final out = await injectClassicAfMarkers(source);
      final outBytes = await out.readAsBytes();
      final decoded = img.decodeImage(outBytes);
      expect(decoded, isNotNull);

      var bright = 0;
      for (final p in decoded!) {
        if (p.r > 200 && p.g > 200 && p.b > 200) bright++;
      }
      expect(bright, greaterThan(80));
    });
  });
}
