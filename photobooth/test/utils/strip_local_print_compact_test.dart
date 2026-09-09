import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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
}
