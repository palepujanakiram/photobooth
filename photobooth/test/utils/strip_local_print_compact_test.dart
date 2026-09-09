import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photobooth/utils/strip_compositor_local.dart';
import 'package:photobooth/utils/strip_local_print_compact.dart';

import '../helpers/tiny_jpeg.dart';

void main() {
  test('compactJpegsForLocalStripPrint leaves empty input empty', () async {
    expect(await compactJpegsForLocalStripPrint(const []), isEmpty);
  });

  test('compactJpegsForLocalStripPrint fails open on an empty plate', () async {
    expect(
      await compactJpegsForLocalStripPrint([Uint8List(0)]),
      isEmpty,
    );
  });

  test('compactJpegsForLocalStripPrint keeps tiny plates', () async {
    final out = await compactJpegsForLocalStripPrint([kTinyJpegBytes]);
    expect(out, hasLength(1));
    expect(out.single, same(kTinyJpegBytes));
  });

  test('compactJpegsForLocalStripPrint keeps the plate when downscale throws',
      () async {
    final out = await compactJpegsForLocalStripPrint(
      [kTinyJpegBytes],
      downscale: (_) async => throw StateError('skia failed'),
    );
    expect(out, hasLength(1));
    expect(out.single, same(kTinyJpegBytes));
  });

  test('compactJpegsForLocalStripPrint accepts a cell-sized long edge',
      () async {
    var calls = 0;
    final out = await compactJpegsForLocalStripPrint(
      [kTinyJpegBytes],
      maxLongEdge: kLocalStripCellJpegMaxLongEdge,
      downscale: (shot) async {
        calls++;
        expect(shot, same(kTinyJpegBytes));
        return shot;
      },
    );
    expect(calls, 1);
    expect(out.single, same(kTinyJpegBytes));
  });

  test('compactOverlayForLocalStripPrint uses landscape and strip dest sizes',
      () async {
    final png = _pngHeader(width: 2000, height: 3000);
    await compactOverlayForLocalStripPrint(
      LocalStripOverlay(pngBytes: png),
      single: true,
      landscape: true,
      resize: (bytes, width, height) async {
        expect(width, kLocalStripSheetHeight);
        expect(height, kLocalStripSheetWidth);
        return bytes;
      },
    );
    await compactOverlayForLocalStripPrint(
      LocalStripOverlay(pngBytes: png),
      single: false,
      landscape: false,
      resize: (bytes, width, height) async {
        expect(
          width,
          (kLocalStripSheetWidth - kLocalStripCenterGutter) ~/ 2,
        );
        expect(height, kLocalStripSheetHeight);
        return bytes;
      },
    );
  });

  test('compactOverlayForLocalStripPrint skips pngs already within the sheet',
      () async {
    final png = _solidPng(20, 30);
    final overlay = LocalStripOverlay(pngBytes: png);
    var resized = 0;
    final out = await compactOverlayForLocalStripPrint(
      overlay,
      single: true,
      landscape: false,
      resize: (_, __, ___) async {
        resized++;
        return Uint8List(0);
      },
    );
    expect(resized, 0);
    expect(out, isNotNull);
    expect(out!.pngBytes, same(png));
  });

  test('compactOverlayForLocalStripPrint resizes an oversized overlay',
      () async {
    final png = _pngHeader(width: 2000, height: 3000);
    final scaled = _solidPng(12, 18);
    final out = await compactOverlayForLocalStripPrint(
      LocalStripOverlay(pngBytes: png),
      single: true,
      landscape: false,
      resize: (bytes, width, height) async {
        expect(bytes, same(png));
        expect(width, kLocalStripSheetWidth);
        expect(height, kLocalStripSheetHeight);
        return scaled;
      },
    );
    expect(out, isNotNull);
    expect(out!.pngBytes, same(scaled));
  });

  test('compactOverlayForLocalStripPrint drops huge overlay when resize is empty',
      () async {
    final huge = _pngHeader(
      width: 4096,
      height: 6144,
      extraBytes: kLocalOverlayIsolateMaxBytes + 8,
    );
    final out = await compactOverlayForLocalStripPrint(
      LocalStripOverlay(pngBytes: huge),
      single: true,
      landscape: false,
      resize: (_, __, ___) async => Uint8List(0),
    );
    expect(out, isNull);
  });

  test('compactOverlayForLocalStripPrint drops a huge overlay when Skia fails',
      () async {
    final huge = _pngHeader(
      width: 4096,
      height: 6144,
      extraBytes: kLocalOverlayIsolateMaxBytes + 8,
    );
    final out = await compactOverlayForLocalStripPrint(
      LocalStripOverlay(pngBytes: huge),
      single: true,
      landscape: false,
      resize: (_, __, ___) async => throw StateError('skia failed'),
    );
    expect(out, isNull);
  });

  test('compactOverlayForLocalStripPrint keeps a small overlay when Skia fails',
      () async {
    final png = _pngHeader(width: 2000, height: 3000);
    final overlay = LocalStripOverlay(pngBytes: png);
    final out = await compactOverlayForLocalStripPrint(
      overlay,
      single: true,
      landscape: false,
      resize: (_, __, ___) async => throw StateError('skia failed'),
    );
    expect(out, isNotNull);
    expect(out!.pngBytes, same(png));
  });

  test('compactOverlayForLocalStripPrint passes through null and empty',
      () async {
    expect(
      await compactOverlayForLocalStripPrint(
        null,
        single: true,
        landscape: false,
      ),
      isNull,
    );
    final empty = LocalStripOverlay(pngBytes: Uint8List(0));
    expect(
      await compactOverlayForLocalStripPrint(
        empty,
        single: true,
        landscape: false,
      ),
      same(empty),
    );
  });
}

Uint8List _solidPng(int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(0, 160, 40, 255));
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _pngHeader({
  required int width,
  required int height,
  int extraBytes = 24,
}) {
  final out = Uint8List(extraBytes < 24 ? 24 : extraBytes);
  out[0] = 0x89;
  out[1] = 0x50;
  out[2] = 0x4E;
  out[3] = 0x47;
  out[16] = (width >> 24) & 0xFF;
  out[17] = (width >> 16) & 0xFF;
  out[18] = (width >> 8) & 0xFF;
  out[19] = width & 0xFF;
  out[20] = (height >> 24) & 0xFF;
  out[21] = (height >> 16) & 0xFF;
  out[22] = (height >> 8) & 0xFF;
  out[23] = height & 0xFF;
  return out;
}
