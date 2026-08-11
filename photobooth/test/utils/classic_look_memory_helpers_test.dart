import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/classic_look_memory_helpers.dart';

void main() {
  group('shouldDeferClassicComposePreviewWarm', () {
    test('defers for 4-shot strips', () {
      expect(
        shouldDeferClassicComposePreviewWarm(
          imageDataUrls: List.filled(4, 'data:image/jpeg;base64,abc'),
        ),
        isTrue,
      );
    });

    test('defers when base64 payload is large', () {
      expect(
        shouldDeferClassicComposePreviewWarm(
          imageDataUrls: ['x' * 800000],
        ),
        isTrue,
      );
    });

    test('allows warm for small 1-shot payloads', () {
      expect(
        shouldDeferClassicComposePreviewWarm(
          imageDataUrls: ['data:image/jpeg;base64,tiny'],
        ),
        isFalse,
      );
    });
  });

  group('classicLookBakeMaxEdge', () {
    test('uses compact edge for 4-shot', () {
      expect(
        classicLookBakeMaxEdge(
          imageDataUrls: List.filled(4, 'data:image/jpeg;base64,abc'),
        ),
        1400,
      );
    });

    test('uses full edge for small 1-shot', () {
      expect(
        classicLookBakeMaxEdge(imageDataUrls: ['data:image/jpeg;base64,tiny']),
        2400,
      );
    });
  });

  group('shouldBakeClassicLooksSequentially', () {
    test('is true for multi-shot strips', () {
      expect(
        shouldBakeClassicLooksSequentially(
          imageDataUrls: List.filled(4, 'data:image/jpeg;base64,abc'),
        ),
        isTrue,
      );
    });
  });
}
