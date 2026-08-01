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
    expect(isAppNormalizedCapturePath('/tmp/tiny.jpg'), isFalse);
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
}
