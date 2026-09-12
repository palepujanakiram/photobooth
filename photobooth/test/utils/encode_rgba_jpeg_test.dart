import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photobooth/utils/encode_rgba_jpeg.dart';

void main() {
  Uint8List solidRgba({required int width, required int height}) {
    final pixels = Uint8List(width * height * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = 200;
      pixels[i + 1] = 10;
      pixels[i + 2] = 10;
      pixels[i + 3] = 255;
    }
    return pixels;
  }

  test('encodeRgbaToJpegDart writes a JPEG of the source size', () {
    final jpeg = encodeRgbaToJpegDart(
      rgba: solidRgba(width: 8, height: 6),
      width: 8,
      height: 6,
      quality: 80,
    );
    final decoded = img.decodeJpg(jpeg);
    expect(decoded, isNotNull);
    expect(decoded!.width, 8);
    expect(decoded.height, 6);
  });

  test('encodeRgbaToJpeg uses native bytes when the channel succeeds', () async {
    final native = Uint8List.fromList([1, 2, 3]);
    final out = await encodeRgbaToJpeg(
      rgba: solidRgba(width: 2, height: 2),
      width: 2,
      height: 2,
      nativeEncode: ({
        required Uint8List rgba,
        required int width,
        required int height,
        required int quality,
      }) async =>
          native,
    );
    expect(out, native);
  });

  test('encodeRgbaToJpeg falls back when native encode is empty', () async {
    final out = await encodeRgbaToJpeg(
      rgba: solidRgba(width: 4, height: 4),
      width: 4,
      height: 4,
      nativeEncode: ({
        required Uint8List rgba,
        required int width,
        required int height,
        required int quality,
      }) async =>
          Uint8List(0),
    );
    expect(img.decodeJpg(out), isNotNull);
  });

  test('encodeRgbaToJpeg falls back when native encode throws', () async {
    final out = await encodeRgbaToJpeg(
      rgba: solidRgba(width: 4, height: 4),
      width: 4,
      height: 4,
      nativeEncode: ({
        required Uint8List rgba,
        required int width,
        required int height,
        required int quality,
      }) async {
        throw StateError('channel down');
      },
    );
    expect(img.decodeJpg(out), isNotNull);
  });
}
