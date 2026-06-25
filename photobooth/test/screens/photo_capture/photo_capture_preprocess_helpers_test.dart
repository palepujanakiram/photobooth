import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/preprocess_image_result.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_preprocess_helpers.dart';

// ignore_for_file: avoid_redundant_argument_values

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

    test('false when session personCount provides signal', () {
      expect(
        isHardPreprocessFailure(
          preprocess: const PreprocessImageResult(success: false),
          clientFaceCount: 0,
          sessionPersonCount: 2,
        ),
        isFalse,
      );
    });

    test('false when preprocess personCount present despite success=false', () {
      expect(
        isHardPreprocessFailure(
          preprocess: const PreprocessImageResult(success: false, personCount: 1),
          clientFaceCount: 0,
        ),
        isFalse,
      );
    });
  });

  group('PreprocessImageResult.fromJson', () {
    test('parses success and int personCount', () {
      final r = PreprocessImageResult.fromJson({
        'success': true,
        'personCount': 2,
      });
      expect(r.success, isTrue);
      expect(r.personCount, 2);
      expect(r.framing, isNull);
    });

    test('parses num personCount via round()', () {
      final r = PreprocessImageResult.fromJson({
        'success': true,
        'personCount': 2.7,
      });
      expect(r.personCount, 3);
    });

    test('parses framing map', () {
      final r = PreprocessImageResult.fromJson({
        'success': true,
        'framing': {'x': 10, 'y': 20},
      });
      expect(r.framing, {'x': 10, 'y': 20});
    });

    test('ignores zero personCount', () {
      final r = PreprocessImageResult.fromJson({'success': true, 'personCount': 0});
      expect(r.personCount, isNull);
    });

    test('empty map defaults', () {
      final r = PreprocessImageResult.fromJson({});
      expect(r.success, isFalse);
      expect(r.personCount, isNull);
      expect(r.framing, isNull);
    });
  });
}
