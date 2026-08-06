import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photobooth/utils/image_helper.dart';

import '../helpers/tiny_jpeg.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getTemporaryDirectory' ||
            call.method == 'getApplicationSupportDirectory') {
          return '/tmp';
        }
        return null;
      },
    );
  });
  test('strip capture jpeg quality is higher than default stills', () {
    expect(kStripCapturedPhotoJpegQuality, greaterThan(kCapturedPhotoJpegQuality));
    expect(kStripCapturedPhotoJpegQuality, 97);
    expect(
      kStripCapturedPhotoMaxDimension,
      greaterThan(kCapturedPhotoMaxDimension),
    );
  });

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

  test('bakeExifAndQuarterTurns rotates clockwise quarter turns', () async {
    final landscape = img.Image(width: 30, height: 10);
    img.fill(landscape, color: img.ColorRgb8(0, 0, 0));
    final jpeg = Uint8List.fromList(img.encodeJpg(landscape, quality: 90));
    final saved = await ImageHelper.bakeExifAndQuarterTurns(
      XFile.fromData(jpeg, mimeType: 'image/jpeg', name: 't.jpg'),
      quarterTurns: 1,
    );
    final meta = await ImageHelper.getImageMetadata(saved);
    expect(meta, isNotNull);
    expect(meta!.width, 10);
    expect(meta.height, 30);
  });
}
