import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/preprocess_image_result.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_preprocess_helpers.dart';

void main() {
  group('resolvePersonCountAfterPreprocess', () {
    test('prefers preprocess personCount', () {
      expect(
        resolvePersonCountAfterPreprocess(
          preprocess: const PreprocessImageResult(success: true, personCount: 3),
          clientFaceCount: 1,
          sessionPersonCount: 2,
        ),
        3,
      );
    });

    test('uses session personCount when preprocess missing', () {
      expect(
        resolvePersonCountAfterPreprocess(
          preprocess: null,
          clientFaceCount: 0,
          sessionPersonCount: 2,
        ),
        2,
      );
    });

    test('uses client face count when preprocess missing', () {
      expect(
        resolvePersonCountAfterPreprocess(
          preprocess: null,
          clientFaceCount: 2,
        ),
        2,
      );
    });

    test('defaults to solo when no signals', () {
      expect(
        resolvePersonCountAfterPreprocess(
          preprocess: null,
          clientFaceCount: 0,
        ),
        1,
      );
    });
  });

  group('isHardPreprocessFailure', () {
    test('false when preprocess succeeded', () {
      expect(
        isHardPreprocessFailure(
          preprocess: const PreprocessImageResult(success: true),
          clientFaceCount: 0,
        ),
        isFalse,
      );
    });

    test('false when client detected faces', () {
      expect(
        isHardPreprocessFailure(
          preprocess: const PreprocessImageResult(success: false),
          clientFaceCount: 2,
        ),
        isFalse,
      );
    });

    test('true only on explicit failure with no count signals', () {
      expect(
        isHardPreprocessFailure(
          preprocess: const PreprocessImageResult(success: false),
          clientFaceCount: 0,
        ),
        isTrue,
      );
    });
  });
}
