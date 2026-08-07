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

  test('bakeExifAndQuarterTurns rotates sensor pixels clockwise', () async {
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

  test('bake with live turns applies Skia EXIF then clockwise turns', () async {
    // 40×20 + EXIF 6 → Skia yields 20×40; +90° CW → 40×20.
    final landscape = img.Image(width: 40, height: 20);
    img.fill(landscape, color: img.ColorRgb8(10, 20, 30));
    landscape.exif.imageIfd.orientation = 6;
    final jpeg = Uint8List.fromList(img.encodeJpg(landscape, quality: 90));

    final saved = await ImageHelper.bakeExifAndQuarterTurns(
      XFile.fromData(jpeg, mimeType: 'image/jpeg', name: 'exif6.jpg'),
      quarterTurns: 1,
    );
    final meta = await ImageHelper.getImageMetadata(saved);
    expect(meta, isNotNull);
    expect(meta!.width, 40);
    expect(meta.height, 20);
  });

  test('bake with zero turns applies EXIF orientation into pixels', () async {
    final landscape = img.Image(width: 40, height: 20);
    img.fill(landscape, color: img.ColorRgb8(1, 2, 3));
    landscape.exif.imageIfd.orientation = 6;
    final jpeg = Uint8List.fromList(img.encodeJpg(landscape, quality: 90));
    final saved = await ImageHelper.bakeExifAndQuarterTurns(
      XFile.fromData(jpeg, mimeType: 'image/jpeg', name: 'exif-only.jpg'),
      quarterTurns: 0,
    );
    final meta = await ImageHelper.getImageMetadata(saved);
    expect(meta, isNotNull);
    expect(meta!.width, 20);
    expect(meta.height, 40);
  });

  test('bake with zero turns skips re-encode when Orientation is 1', () async {
    final landscape = img.Image(width: 40, height: 20);
    img.fill(landscape, color: img.ColorRgb8(1, 2, 3));
    final jpeg = Uint8List.fromList(img.encodeJpg(landscape, quality: 90));
    final source = XFile.fromData(
      jpeg,
      mimeType: 'image/jpeg',
      name: 'upright.jpg',
    );
    final saved = await ImageHelper.bakeExifAndQuarterTurns(
      source,
      quarterTurns: 0,
    );
    expect(identical(saved, source), isTrue);
  });

  test('bake with live 180° on EXIF-6 keeps Skia-upright portrait', () async {
    // Skia applies EXIF 6 → 20×40; +180° stays 20×40.
    final landscape = img.Image(width: 40, height: 20);
    img.fill(landscape, color: img.ColorRgb8(5, 6, 7));
    landscape.exif.imageIfd.orientation = 6;
    final jpeg = Uint8List.fromList(img.encodeJpg(landscape, quality: 90));
    final saved = await ImageHelper.bakeExifAndQuarterTurns(
      XFile.fromData(jpeg, mimeType: 'image/jpeg', name: 'exif6-180.jpg'),
      quarterTurns: 2,
    );
    final meta = await ImageHelper.getImageMetadata(saved);
    expect(meta, isNotNull);
    expect(meta!.width, 20);
    expect(meta.height, 40);
  });

  test('bake quarterTurns 3 rotates untagged landscape to portrait', () async {
    final landscape = img.Image(width: 40, height: 20);
    img.fill(landscape, color: img.ColorRgb8(8, 9, 10));
    final jpeg = Uint8List.fromList(img.encodeJpg(landscape, quality: 90));
    final saved = await ImageHelper.bakeExifAndQuarterTurns(
      XFile.fromData(jpeg, mimeType: 'image/jpeg', name: 'force3.jpg'),
      quarterTurns: 3,
    );
    final meta = await ImageHelper.getImageMetadata(saved);
    expect(meta, isNotNull);
    expect(meta!.width, 20);
    expect(meta.height, 40);
  });
}
