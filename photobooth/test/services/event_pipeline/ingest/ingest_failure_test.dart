import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/event_pipeline/ingest/ingest_failure.dart';

void main() {
  group('classify', () {
    test('the native downscaler reporting a vanished item is source-gone', () {
      // Verbatim shape of EventImageDownscaler.kt's error once the volume goes.
      expect(
        IngestFailure.classify(PlatformException(
          code: 'downscale_failed',
          message: 'java.io.FileNotFoundException: content://media/1e6f-0961/'
              'images/media/42: open failed: ENOENT (No such file or directory)',
        )),
        IngestFailureKind.sourceUnavailable,
      );
    });

    test('a missing MediaStore volume is source-gone', () {
      expect(
        IngestFailure.classify(PlatformException(
          code: 'downscale_failed',
          message: 'Volume 1e6f-0961 not found',
        )),
        IngestFailureKind.sourceUnavailable,
      );
    });

    test('a decode failure on a readable card is the photo’s fault', () {
      expect(
        IngestFailure.classify(PlatformException(
          code: 'downscale_failed',
          message: "ImageDecoder\$DecodeException: Failed to create image "
              "decoder with message 'unimplemented'",
        )),
        IngestFailureKind.item,
      );
    });

    test('an ENOENT FileSystemException is source-gone', () {
      expect(
        IngestFailure.classify(const FileSystemException(
          'Cannot open file',
          '/storage/1E6F-0961/DCIM/IMG_0001.JPG',
          OSError('No such file or directory', 2),
        )),
        IngestFailureKind.sourceUnavailable,
      );
    });

    test('an I/O error on the medium is source-gone', () {
      expect(
        IngestFailure.classify(const FileSystemException(
          'Read failed',
          '/storage/1E6F-0961/DCIM/IMG_0001.JPG',
          OSError('Input/output error', 5),
        )),
        IngestFailureKind.sourceUnavailable,
      );
    });

    test('a filesystem error with no errno falls back to the message', () {
      expect(
        IngestFailure.classify(
          const FileSystemException('Something odd', '/tmp/x'),
        ),
        IngestFailureKind.item,
      );
    });

    test('an unrecognised error is the photo’s fault, which is the safe way', () {
      // A wrongly-FAILED photo stays visible and retryable; a wrongly-deleted
      // row is only visible as "already imported", which is a lie.
      expect(
        IngestFailure.classify(StateError('cannot decode /DCIM/B.JPG')),
        IngestFailureKind.item,
      );
    });

    test('a StateError that names a missing file is still source-gone', () {
      expect(
        IngestFailure.classify(StateError('no such file on the card')),
        IngestFailureKind.sourceUnavailable,
      );
    });
  });

  group('isUnreachableUri', () {
    test('an empty or blank uri cannot be opened', () {
      expect(IngestFailure.isUnreachableUri(''), isTrue);
      expect(IngestFailure.isUnreachableUri('   '), isTrue);
    });

    test('a real uri is reachable', () {
      expect(
        IngestFailure.isUnreachableUri('content://media/external/images/media/1'),
        isFalse,
      );
    });
  });
}
