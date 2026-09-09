import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_pipeline/media_rendition.dart';
import 'package:photobooth/services/event_pipeline/frame_compositor.dart';
import 'package:photobooth/services/event_pipeline/ingest/image_downscaler.dart';
import 'dart:typed_data';

void main() {
  group('RenditionKind', () {
    test('knows the kinds it stores', () {
      for (final kind in RenditionKind.all) {
        expect(RenditionKind.isValid(kind), isTrue, reason: kind);
      }
      expect(RenditionKind.isValid('overlay'), isFalse);
    });

    test('a thumbnail is never a print candidate', () {
      // A 320px thumbnail reaching a printer is the one mistake this ordering
      // exists to prevent.
      expect(RenditionKind.printPriority, isNot(contains(RenditionKind.thumb)));
      final best = MediaRendition.bestForPrint(const [
        MediaRendition(
          mediaId: 'm1',
          kind: RenditionKind.thumb,
          path: 't.jpg',
          createdAtMs: 1,
        ),
      ]);
      expect(best, isNull);
    });
  });

  group('hasThumb', () {
    test('a downscale reports whether it produced one', () {
      final without = DownscaleResult(
        bytes: Uint8List(4),
        width: 1,
        height: 1,
      );
      expect(without.hasThumb, isFalse);

      final withThumb = DownscaleResult(
        bytes: Uint8List(4),
        width: 1,
        height: 1,
        thumbBytes: Uint8List.fromList([1, 2]),
      );
      expect(withThumb.hasThumb, isTrue);
    });

    test('an empty thumbnail buffer counts as none', () {
      final result = DownscaleResult(
        bytes: Uint8List(4),
        width: 1,
        height: 1,
        thumbBytes: Uint8List(0),
      );
      expect(result.hasThumb, isFalse);
    });

    test('a composite reports the same way', () {
      final without = CompositeResult(
        bytes: Uint8List(4),
        width: 1,
        height: 1,
      );
      expect(without.hasThumb, isFalse);

      final withThumb = CompositeResult(
        bytes: Uint8List(4),
        width: 1,
        height: 1,
        thumbBytes: Uint8List.fromList([9]),
      );
      expect(withThumb.hasThumb, isTrue);
    });
  });
}
