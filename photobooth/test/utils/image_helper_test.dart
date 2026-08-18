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
    expect(kStripCapturedPhotoJpegQuality, 92);
    expect(kDnpPrintJpegQuality, kStripCapturedPhotoJpegQuality);
    expect(
      kStripCapturedPhotoMaxDimension,
      kCapturedPhotoMaxDimension,
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

  test('bake quarterTurns -1 rotates 90° CCW (left)', () async {
    final landscape = img.Image(width: 40, height: 20);
    img.fill(landscape, color: img.ColorRgb8(8, 9, 10));
    final jpeg = Uint8List.fromList(img.encodeJpg(landscape, quality: 90));
    final saved = await ImageHelper.bakeExifAndQuarterTurns(
      XFile.fromData(jpeg, mimeType: 'image/jpeg', name: 'force-left.jpg'),
      quarterTurns: -1,
    );
    final meta = await ImageHelper.getImageMetadata(saved);
    expect(meta, isNotNull);
    // 90° CCW on 40×20 → 20×40
    expect(meta!.width, 20);
    expect(meta.height, 40);
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

  test('peekJpegSofDimensions reads tiny jpeg size', () {
    final size = peekJpegSofDimensions(kTinyJpegBytes);
    expect(size, isNotNull);
    expect(size!.width, 2);
    expect(size.height, 2);
  });

  test('meanJpegLuma reads tiny jpeg and rejects non-jpeg', () async {
    final luma = await meanJpegLuma(kTinyJpegBytes);
    expect(luma, isNotNull);
    expect(luma, inInclusiveRange(0, 255));
    expect(await meanJpegLuma(Uint8List(0)), isNull);
    expect(await meanJpegLuma(Uint8List.fromList([0x00, 0x01])), isNull);
    expect(await meanJpegLuma(kTinyJpegBytes, sampleWidth: 0), isNull);
  });

  test('peekJpegSofDimensions rejects truncated and non-jpeg', () {
    expect(peekJpegSofDimensions([]), isNull);
    expect(peekJpegSofDimensions([0x49, 0x49, 0x2a, 0x00]), isNull);
    expect(peekJpegSofDimensions([0xFF, 0xD8]), isNull);
    expect(peekJpegSofDimensions([0xFF, 0xD8, 0xFF]), isNull);
    expect(peekJpegSofDimensions([0xFF, 0xD8, 0xFF, 0xC0]), isNull);
    expect(peekJpegSofDimensions([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x01]), isNull);
    expect(
      peekJpegSofDimensions([0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x0B, 0x08]),
      isNull,
    );
  });

  test('peekJpegSofDimensions skips padding RST SOI and reads SOF', () {
    List<int> sof(int marker, int width, int height) => [
          0xFF,
          marker,
          0x00,
          0x0B,
          0x08,
          height >> 8,
          height & 0xFF,
          width >> 8,
          width & 0xFF,
          0x03,
          0x01,
          0x22,
          0x00,
        ];
    expect(
      peekJpegSofDimensions([0xFF, 0xD8, 0x00, 0xFF, 0xD0, ...sof(0xC0, 2, 3)]),
      (width: 2, height: 3),
    );
    expect(
      peekJpegSofDimensions([0xFF, 0xD8, 0xFF, 0xD8, ...sof(0xC1, 4, 5)]),
      (width: 4, height: 5),
    );
    expect(
      peekJpegSofDimensions([0xFF, 0xD8, 0xFF, 0x01, ...sof(0xC2, 6, 7)]),
      (width: 6, height: 7),
    );
    expect(
      peekJpegSofDimensions([0xFF, 0xD8, 0xFF, 0xD9, ...sof(0xC3, 8, 9)]),
      (width: 8, height: 9),
    );
    expect(
      peekJpegSofDimensions(sof(0xC0, 0, 0)..insertAll(0, [0xFF, 0xD8])),
      isNull,
    );
  });

  test('downscaleJpegToMaxLongEdge leaves small stills unchanged', () async {
    final raw = XFile.fromData(
      kTinyJpegBytes,
      mimeType: 'image/jpeg',
      name: 't.jpg',
    );
    final out = await ImageHelper.downscaleJpegToMaxLongEdge(raw);
    expect(identical(out, raw), isTrue);
  });

  test('downscaleJpegToMaxLongEdge shrinks landscape and portrait stills',
      () async {
    final landscape = img.Image(width: 400, height: 200);
    img.fill(landscape, color: img.ColorRgb8(12, 12, 12));
    final landOut = await ImageHelper.downscaleJpegToMaxLongEdge(
      XFile.fromData(
        Uint8List.fromList(img.encodeJpg(landscape, quality: 90)),
        mimeType: 'image/jpeg',
        name: 'w.jpg',
      ),
      maxLongEdge: 100,
    );
    final landDecoded = img.decodeImage(await landOut.readAsBytes());
    expect(landDecoded, isNotNull);
    expect(landDecoded!.width, 100);
    expect(landDecoded.height, 50);

    final portrait = img.Image(width: 100, height: 400);
    img.fill(portrait, color: img.ColorRgb8(12, 12, 12));
    final portOut = await ImageHelper.downscaleJpegToMaxLongEdge(
      XFile.fromData(
        Uint8List.fromList(img.encodeJpg(portrait, quality: 90)),
        mimeType: 'image/jpeg',
        name: 'h.jpg',
      ),
      maxLongEdge: 80,
    );
    final portDecoded = img.decodeImage(await portOut.readAsBytes());
    expect(portDecoded, isNotNull);
    expect(portDecoded!.height, 80);
    expect(portDecoded.width, 20);
  });

  test('downscaleJpegToMaxLongEdge throws on empty bytes', () async {
    await expectLater(
      ImageHelper.downscaleJpegToMaxLongEdge(
        XFile.fromData(Uint8List(0), mimeType: 'image/jpeg', name: 'e.jpg'),
      ),
      throwsA(isA<Exception>()),
    );
  });
}
