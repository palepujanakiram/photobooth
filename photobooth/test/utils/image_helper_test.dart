import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/image_helper.dart';

import '../helpers/tiny_jpeg.dart';

void main() {
  test('formatFileSize labels B KB MB', () {
    expect(ImageHelper.formatFileSize(500), '500 B');
    expect(ImageHelper.formatFileSize(2048), '2 KB');
    expect(ImageHelper.formatFileSize(3 * 1024 * 1024), '3.0 MB');
  });

  test('getImageMetadata decodes tiny jpeg', () async {
    final meta = await ImageHelper.getImageMetadata(tinyJpegXFile());
    expect(meta, isNotNull);
    expect(meta!.width, greaterThan(0));
    expect(meta.format, 'JPEG');
  });

  test('resizeAndEncodeImage returns data url', () async {
    final url = await ImageHelper.resizeAndEncodeImage(tinyJpegXFile());
    expect(url, startsWith('data:image/jpeg;base64,'));
  });

  test('encodeImageForUpload uses session patch encoder', () async {
    final url = await ImageHelper.encodeImageForUpload(tinyJpegXFile());
    expect(url, startsWith('data:image/jpeg;base64,'));
  });
}
