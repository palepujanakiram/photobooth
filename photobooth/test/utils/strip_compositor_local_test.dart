import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photobooth/services/local_media_store.dart';
import 'package:photobooth/utils/print_orientation.dart';
import 'package:photobooth/utils/strip_compositor_local.dart';

void main() {
  group('local Classic compositor', () {
    test('builds a full-size dual strip JPEG from four small plates', () {
      final sources = <Uint8List>[
        _solidJpeg(220, 20, 20, width: 40, height: 20),
        _solidJpeg(20, 220, 20),
        _solidJpeg(20, 20, 220),
        _solidJpeg(220, 180, 20),
      ];

      final jpeg = composeLocalStripSheetJpegForTest(
        sourceBytes: sources,
        filterId: 'classic_warm',
        frameId: 'filmstrip',
        single: false,
      );

      expect(jpeg, isNotEmpty);
      final decoded = img.decodeJpg(jpeg);
      expect(decoded, isNotNull);
      expect(decoded!.width, kLocalStripSheetWidth);
      expect(decoded.height, kLocalStripSheetHeight);
    });

    test('three plates fill the same sheet with taller cells', () {
      final sources = <Uint8List>[
        _solidJpeg(220, 20, 20, width: 40, height: 20),
        _solidJpeg(20, 220, 20),
        _solidJpeg(20, 20, 220),
      ];

      final jpeg = composeLocalStripSheetJpegForTest(
        sourceBytes: sources,
        filterId: 'clean',
        frameId: 'classic',
        single: false,
      );

      final decoded = img.decodeJpg(jpeg);
      expect(decoded, isNotNull);
      // Print sheet size never changes with the shot count.
      expect(decoded!.width, kLocalStripSheetWidth);
      expect(decoded.height, kLocalStripSheetHeight);

      // Each of the three cells is ~597px tall, so sampling a third of the way
      // down lands in a different plate than the four-shot layout would.
      const cellHeight = (kLocalStripSheetHeight - kLocalStripBorder * 2) ~/ 3;
      final firstCell = decoded.getPixel(300, kLocalStripBorder + 50);
      final secondCell =
          decoded.getPixel(300, kLocalStripBorder + cellHeight + 50);
      final thirdCell =
          decoded.getPixel(300, kLocalStripBorder + cellHeight * 2 + 50);
      expect(firstCell.r, greaterThan(firstCell.g));
      expect(secondCell.g, greaterThan(secondCell.r));
      expect(thirdCell.b, greaterThan(thirdCell.r));
    });

    test('rejects a strip length the print cannot lay out', () async {
      final dataUrl =
          'data:image/jpeg;base64,${base64Encode(_solidJpeg(10, 10, 10))}';
      final twoShot = LocalStripComposeRequest(
        sources: [dataUrl, dataUrl],
        filterId: 'clean',
        frameId: 'classic',
        single: false,
        orientation: PrintOrientation.portrait,
      );
      expect(await composeLocalStripSheet(twoShot), isNull);

      // An explicit shotCount that disagrees with the sources also fails open.
      final mismatched = LocalStripComposeRequest(
        sources: [dataUrl, dataUrl, dataUrl],
        filterId: 'clean',
        frameId: 'classic',
        single: false,
        shotCount: 4,
        orientation: PrintOrientation.portrait,
      );
      expect(await composeLocalStripSheet(mismatched), isNull);
    });

    test('loads a file and persists a landscape single sheet', () async {
      final temp = await Directory.systemTemp.createTemp('local-strip-test');
      addTearDown(() => temp.delete(recursive: true));
      final source = File('${temp.path}/source.jpg');
      await source.writeAsBytes(_solidJpeg(40, 80, 160));
      final store = LocalMediaStore(resolveDirectory: () async => temp);

      final url = await composeLocalStripSheet(
        LocalStripComposeRequest(
          sources: [Uri.file(source.path).toString()],
          filterId: 'clean',
          frameId: 'classic',
          single: true,
          orientation: PrintOrientation.landscape,
          mediaStore: store,
        ),
      );

      expect(url, startsWith('/api/img/fotoflashback/'));
      final output = await store.fileForUrl(url!);
      expect(output, isNotNull);
      final decoded = img.decodeJpg(await output!.readAsBytes());
      expect(decoded, isNotNull);
      expect(decoded!.width, kLocalStripSheetHeight);
      expect(decoded.height, kLocalStripSheetWidth);
    });

    test('returns inline JPEG when local persistence is unavailable', () async {
      final source = _solidJpeg(120, 80, 40, width: 40, height: 20);
      final dataUrl = 'data:image/jpeg;base64,${base64Encode(source)}';
      final unavailable =
          LocalMediaStore(resolveDirectory: () => throw StateError('no disk'));

      final url = await composeLocalStripSheet(
        LocalStripComposeRequest(
          sources: [dataUrl],
          filterId: 'mono',
          frameId: 'noir',
          single: true,
          orientation: PrintOrientation.portrait,
          mediaStore: unavailable,
        ),
      );

      expect(url, startsWith('data:image/jpeg;base64,'));
      final bytes = base64Decode(url!.split(',').last);
      final decoded = img.decodeJpg(bytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, kLocalStripSheetWidth);
      expect(decoded.height, kLocalStripSheetHeight);
    });

    test('loads a source through a local-media URL', () async {
      final temp = await Directory.systemTemp.createTemp('local-strip-store');
      addTearDown(() => temp.delete(recursive: true));
      final store = LocalMediaStore(resolveDirectory: () async => temp);
      final ref = LocalMediaRef.fromParts(
        kGuestMediaPrefixUserUploads,
        'source.jpg',
      )!;
      await store.putBytes(ref, _solidJpeg(10, 30, 90));

      final url = await composeLocalStripSheet(
        LocalStripComposeRequest(
          sources: ['/api/img/${ref.relativePath}'],
          filterId: 'clean',
          frameId: 'classic',
          single: true,
          orientation: PrintOrientation.portrait,
          mediaStore: store,
        ),
      );

      expect(url, startsWith('/api/img/fotoflashback/'));
    });

    test('fails open for missing and unreadable sources', () async {
      final temp = await Directory.systemTemp.createTemp('local-strip-errors');
      addTearDown(() => temp.delete(recursive: true));
      final request = LocalStripComposeRequest(
        sources: ['${temp.path}/missing.jpg'],
        filterId: 'clean',
        frameId: 'classic',
        single: true,
        orientation: PrintOrientation.portrait,
        mediaStore: LocalMediaStore(resolveDirectory: () async => temp),
      );
      expect(await composeLocalStripSheet(request), isNull);

      final throwingRequest = LocalStripComposeRequest(
        sources: [temp.path],
        filterId: 'clean',
        frameId: 'classic',
        single: true,
        orientation: PrintOrientation.portrait,
        mediaStore: _ThrowingMediaStore(),
      );
      expect(await composeLocalStripSheet(throwingRequest), isNull);
    });
  });

  test('contain-fit resizes landscape and portrait plates', () {
    final wide = prepareLocalStripCellForTest(
      _solidJpeg(10, 20, 30, width: 80, height: 20),
      40,
      40,
      contain: true,
    );
    expect(wide, isNotNull);
    expect(wide!.width, 40);
    expect(wide.height, 40);

    final tall = prepareLocalStripCellForTest(
      _solidJpeg(30, 20, 10, width: 20, height: 80),
      40,
      40,
      matrix: List<double>.filled(20, 0),
      contain: true,
    );
    expect(tall, isNotNull);
    expect(tall!.width, 40);
  });
}

Uint8List _solidJpeg(
  int red,
  int green,
  int blue, {
  int width = 24,
  int height = 32,
}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(red, green, blue));
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

class _ThrowingMediaStore extends LocalMediaStore {
  @override
  Future<File?> fileForUrl(String url) => throw StateError('read failed');
}
