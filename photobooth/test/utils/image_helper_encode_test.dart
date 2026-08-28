import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/image_helper.dart';
import 'package:photobooth/utils/image_helper_encode.dart';

import '../helpers/tiny_jpeg.dart';

void main() {
  test('tryTrustNormalizedJpegBytesForSessionPatch accepts small jpeg', () {
    final trusted = tryTrustNormalizedJpegBytesForSessionPatch(kTinyJpegBytes);
    expect(trusted, isNotNull);
    expect(trusted, startsWith('data:image/jpeg;base64,'));
  });

  test('isAppNormalizedCapturePath matches app photos dir', () {
    expect(
      isAppNormalizedCapturePath('/data/user/0/app/cache/photos/photo_123.jpg'),
      isTrue,
    );
    expect(
      isAppNormalizedCapturePath('/data/user/0/app/cache/sidecar/fz200d_1.jpg'),
      isTrue,
      reason: 'Pi sidecar JPEGs must skip Dart image re-decode',
    );
    expect(isAppNormalizedCapturePath('/tmp/tiny.jpg'), isFalse);
    expect(
      isAppNormalizedCapturePath(
        '/data/user/0/app/files/fotozen_media/user-uploads/cap.jpg',
      ),
      isTrue,
      reason: 'persistCapturedGuestXFile must keep the trusted upload path',
    );
  });

  group('native direct-PTP display derivative', () {
    const dir = '/data/user/0/app/files/captures/sess-42';

    // Regression, hardware 2026-08-20. Direct PTP was the only capture source
    // whose paths missed this predicate, so it alone paid the pure-Dart
    // decode → cubic resize → re-encode. That work sits inside the 90s
    // kSessionUploadTimeout around _ensureUploadBase64Ready and overran it on an
    // Android TV box: "Upload took too long, check your connection", with the
    // camera and network both fine. EDSDK/Pi were unaffected — `/sidecar/`
    // already short-circuited it.
    test('the derivative is trusted, so the box never re-encodes it', () {
      expect(
        isAppNormalizedCapturePath('$dir/0001_IMG_8309.display.jpg'),
        isTrue,
      );
    });

    // The single most important case here. The derivative lives in the *same*
    // folder as the untouched ~7MB camera original, so a directory-based match
    // would send a 6000x4000 JPEG verbatim into the session PATCH — worse than
    // the bug being fixed. The original must keep taking the resize path.
    test('the full-res original beside it is NOT trusted', () {
      expect(isAppNormalizedCapturePath('$dir/0001_IMG_8309.JPG'), isFalse);
      expect(isAppNormalizedCapturePath('$dir/0002_IMG_8310.jpg'), isFalse);
    });

    test('matching is case-insensitive, as the rest of the predicate is', () {
      expect(
        isAppNormalizedCapturePath('$dir/0001_IMG_8309.DISPLAY.JPG'),
        isTrue,
      );
    });

    test('the suffix constant is what the native side actually writes', () {
      // DisplayDerivative.create() builds "${nameWithoutExtension}.display.jpg".
      // If that name ever changes, this predicate silently stops matching and the
      // TV box regresses to the timeout — so pin the string.
      expect(kNativeDisplayDerivativeSuffix, '.display.jpg');
    });
  });

  test('tryReuseNormalizedJpegForSessionPatch accepts small jpeg', () {
    final reused = tryReuseNormalizedJpegForSessionPatch(kTinyJpegBytes);
    expect(reused, isNotNull);
    expect(reused, startsWith('data:image/jpeg;base64,'));
  });

  test('encodeSessionPatchUserImageUrl reuses normalized jpeg bytes', () {
    final url = encodeSessionPatchUserImageUrl(kTinyJpegBytes);
    expect(url, startsWith('data:image/jpeg;base64,'));
  });

  test('encodeImageForUpload uses trusted path for normalized capture file', () async {
    final dir = Directory.systemTemp.createTempSync('pb_photos_test');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final photosDir = Directory('${dir.path}/photos')..createSync();
    final capturePath = '${photosDir.path}/photo_1.jpg';
    File(capturePath).writeAsBytesSync(kTinyJpegBytes);
    final url = await ImageHelper.encodeImageForUpload(XFile(capturePath));
    expect(url, startsWith('data:image/jpeg;base64,'));
  });

  test('encodeImageForUpload uses trusted path for guest media capture', () async {
    final dir = Directory.systemTemp.createTempSync('pb_guest_media_test');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final guestDir = Directory('${dir.path}/fotozen_media/user-uploads')
      ..createSync(recursive: true);
    final capturePath = '${guestDir.path}/cap.jpg';
    File(capturePath).writeAsBytesSync(kTinyJpegBytes);
    final url = await ImageHelper.encodeImageForUpload(XFile(capturePath));
    expect(url, startsWith('data:image/jpeg;base64,'));
  });
}
