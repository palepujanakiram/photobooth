import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/png_ihdr_peek.dart';

void main() {
  test('peekPngIhhrDimensions reads a real PNG header', () {
    // 1×1 transparent PNG.
    const png = <int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
    ];
    final size = peekPngIhhrDimensions(png);
    expect(size, isNotNull);
    expect(size!.width, 1);
    expect(size.height, 1);
  });

  test('peekPngIhhrDimensions rejects non-PNG bytes', () {
    expect(peekPngIhhrDimensions(Uint8List(0)), isNull);
    expect(peekPngIhhrDimensions(Uint8List.fromList([0xFF, 0xD8])), isNull);
  });

  test('peekPngIhhrDimensions rejects zero dimensions', () {
    final bytes = Uint8List(24);
    bytes[0] = 0x89;
    bytes[1] = 0x50;
    bytes[2] = 0x4E;
    bytes[3] = 0x47;
    expect(peekPngIhhrDimensions(bytes), isNull);
  });
}
