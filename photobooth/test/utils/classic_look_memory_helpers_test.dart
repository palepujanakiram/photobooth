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

    test('still defers warm for compact 4-shot Direct PTP derivatives', () {
      expect(
        shouldDeferClassicComposePreviewWarm(
          imageDataUrls: List.filled(4, 'data:image/jpeg;base64,abc'),
          captureUploadsAlreadyCompact: true,
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

  group('shouldSkipClassicClientLookBake', () {
    test('skips bake for 4-shot strips', () {
      expect(
        shouldSkipClassicClientLookBake(
          imageDataUrls: List.filled(4, 'data:image/jpeg;base64,abc'),
        ),
        isTrue,
      );
    });

    test('skips bake for 1-shot payloads', () {
      expect(
        shouldSkipClassicClientLookBake(
          imageDataUrls: ['data:image/jpeg;base64,tiny'],
        ),
        isTrue,
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

    test('uses compact edge for large 1-shot', () {
      expect(
        classicLookBakeMaxEdge(imageDataUrls: ['x' * 800000]),
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

    test('is true for large 1-shot payloads', () {
      expect(
        shouldBakeClassicLooksSequentially(
          imageDataUrls: ['x' * 800000],
        ),
        isTrue,
      );
    });

    test('is false for small 1-shot payloads', () {
      expect(
        shouldBakeClassicLooksSequentially(
          imageDataUrls: ['data:image/jpeg;base64,tiny'],
        ),
        isFalse,
      );
    });
  });

  group('shouldCompactClassicComposeUploads', () {
    test('skips tiny fixtures', () {
      expect(
        shouldCompactClassicComposeUploads(
          imageDataUrls: List.filled(4, 'data:image/jpeg;base64,abc'),
        ),
        isFalse,
      );
    });

    test('skips when capture already compact', () {
      expect(
        shouldCompactClassicComposeUploads(
          imageDataUrls: List.filled(4, 'x' * 60000),
          captureUploadsAlreadyCompact: true,
        ),
        isFalse,
      );
    });

    test('compacts large 4-shot payloads', () {
      expect(
        shouldCompactClassicComposeUploads(
          imageDataUrls: List.filled(4, 'x' * 60000),
        ),
        isTrue,
      );
    });
  });

  group('classicImagePayloadIsLarge', () {
    test('is false for small payloads', () {
      expect(
        classicImagePayloadIsLarge(imageDataUrls: ['tiny']),
        isFalse,
      );
    });
  });

  group('classicCaptureFilesAreCompactDisplayDerivatives', () {
    test('is true for display derivative paths', () {
      expect(
        classicCaptureFilesAreCompactDisplayDerivatives(
          filePaths: [
            '/tmp/shot1.display.jpg',
            '/tmp/shot2.display.jpg',
          ],
        ),
        isTrue,
      );
    });

    test('is false when any path is not a display derivative', () {
      expect(
        classicCaptureFilesAreCompactDisplayDerivatives(
          filePaths: ['/tmp/shot1.display.jpg', '/tmp/shot2.jpg'],
        ),
        isFalse,
      );
    });

    test('is false for empty paths', () {
      expect(
        classicCaptureFilesAreCompactDisplayDerivatives(filePaths: []),
        isFalse,
      );
    });
  });
}
