import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photobooth/models/strip_models.dart';
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

    test('portrait chrome rect letterboxes 4x6 on a landscape sheet', () {
      final portrait = portraitChromeRectOnSheet(
        kLocalStripSheetWidth,
        kLocalStripSheetHeight,
      );
      expect(portrait.left, 0);
      expect(portrait.top, 0);
      expect(portrait.width, kLocalStripSheetWidth);
      expect(portrait.height, kLocalStripSheetHeight);

      final landscape = portraitChromeRectOnSheet(
        kLocalStripSheetHeight,
        kLocalStripSheetWidth,
      );
      expect(landscape.width, 800);
      expect(landscape.height, kLocalStripSheetWidth);
      expect(landscape.left, 500);
      expect(landscape.top, 0);

      final tall = portraitChromeRectOnSheet(600, kLocalStripSheetHeight);
      expect(tall.width, 600);
      expect(tall.left, 0);
      expect(tall.height, 900);
      expect(tall.top, 450);
    });

    test('covers landscape 6x4 with the photo and contain-fits 4x6 chrome',
        () {
      final overlay = _overlayPng(
        width: 120,
        height: 180,
        holeLeft: 9,
        holeTop: 32,
        holeWidth: 102,
        holeHeight: 108,
      );
      final jpeg = composeLocalStripSheetJpegForTest(
        sourceBytes: [_solidJpeg(220, 20, 20)],
        filterId: 'clean',
        frameId: 'ai:dps-1',
        single: true,
        landscape: true,
        overlay: LocalStripOverlay(
          pngBytes: overlay,
          slots: const [defaultOccasionSinglePhotoHole],
        ),
      );
      final decoded = img.decodeJpg(jpeg)!;
      expect(decoded.width, kLocalStripSheetHeight);
      expect(decoded.height, kLocalStripSheetWidth);
      final edge = decoded.getPixel(20, 600);
      expect(edge.r, greaterThan(edge.g));
      final chrome = decoded.getPixel(900, 20);
      expect(chrome.g, greaterThan(chrome.r));
    });

    test('stamps a 1-shot occasion overlay into the photo hole', () {
      final overlay = _overlayPng(
        width: 120,
        height: 180,
        holeLeft: 9,
        holeTop: 32,
        holeWidth: 102,
        holeHeight: 108,
      );
      final jpeg = composeLocalStripSheetJpegForTest(
        sourceBytes: [_solidJpeg(220, 20, 20)],
        filterId: 'clean',
        frameId: 'ai:dps-1',
        single: true,
        overlay: LocalStripOverlay(
          pngBytes: overlay,
          slots: const [defaultOccasionSinglePhotoHole],
        ),
      );
      final decoded = img.decodeJpg(jpeg)!;
      final photo = decoded.getPixel(600, 900);
      final chrome = decoded.getPixel(20, 20);
      expect(photo.r, greaterThan(photo.g));
      expect(chrome.g, greaterThan(chrome.r));
    });

    test('stamps a 4-shot occasion overlay on both 2x6 halves', () {
      final overlay = _overlayPng(
        width: 60,
        height: 180,
        holeLeft: 5,
        holeTop: 29,
        holeWidth: 50,
        holeHeight: 28,
      );
      final jpeg = composeLocalStripSheetJpegForTest(
        sourceBytes: [
          _solidJpeg(220, 20, 20),
          _solidJpeg(20, 220, 20),
          _solidJpeg(20, 20, 220),
          _solidJpeg(220, 180, 20),
        ],
        filterId: 'clean',
        frameId: 'fr:dps-1',
        single: false,
        overlay: LocalStripOverlay(pngBytes: overlay),
      );
      final decoded = img.decodeJpg(jpeg)!;
      final first = decoded.getPixel(80, 340);
      final chrome = decoded.getPixel(40, 20);
      expect(first.r, greaterThan(first.g));
      expect(chrome.g, greaterThan(chrome.r));
    });

    test('occasion overlay decode failure still lays out the photo hole', () {
      final jpeg = composeLocalStripSheetJpegForTest(
        sourceBytes: [_solidJpeg(20, 20, 220)],
        filterId: 'clean',
        frameId: 'ai:dps-1',
        single: true,
        overlay: LocalStripOverlay(pngBytes: Uint8List(0)),
      );
      expect(jpeg, isNotEmpty);
      composeLocalStripSheetJpegForTest(
        sourceBytes: [_solidJpeg(20, 20, 220)],
        filterId: 'clean',
        frameId: 'ai:dps-1',
        single: true,
        overlay: LocalStripOverlay(pngBytes: Uint8List.fromList([1, 2, 3])),
      );
      composeLocalStripSheetJpegForTest(
        sourceBytes: [_solidJpeg(20, 20, 220)],
        filterId: 'clean',
        frameId: 'ai:dps-1',
        single: true,
        overlay: LocalStripOverlay(pngBytes: _solidJpeg(0, 180, 40)),
      );
    });

    test('persists a 1-shot occasion overlay through the isolate', () async {
      final dataUrl =
          'data:image/jpeg;base64,${base64Encode(_solidJpeg(10, 10, 10))}';
      final url = await composeLocalStripSheet(
        LocalStripComposeRequest(
          sources: [dataUrl],
          filterId: 'clean',
          frameId: 'ai:dps-1',
          single: true,
          orientation: PrintOrientation.portrait,
          overlay: LocalStripOverlay(
            pngBytes: _overlayPng(
              width: 40,
              height: 60,
              holeLeft: 3,
              holeTop: 10,
              holeWidth: 34,
              holeHeight: 36,
            ),
            slots: const [defaultOccasionSinglePhotoHole],
          ),
        ),
      );
      expect(url, isNotNull);
    });

    test('persists a 4-shot occasion overlay through the isolate', () async {
      final dataUrl =
          'data:image/jpeg;base64,${base64Encode(_solidJpeg(10, 10, 10))}';
      final url = await composeLocalStripSheet(
        LocalStripComposeRequest(
          sources: [dataUrl, dataUrl, dataUrl, dataUrl],
          filterId: 'clean',
          frameId: 'fr:dps-1',
          single: false,
          orientation: PrintOrientation.portrait,
          overlay: LocalStripOverlay(
            pngBytes: _overlayPng(
              width: 40,
              height: 120,
              holeLeft: 3,
              holeTop: 20,
              holeWidth: 34,
              holeHeight: 20,
            ),
          ),
        ),
      );
      expect(url, isNotNull);
    });

    test('uses catalog slots when the overlay lists one cell per shot', () {
      final jpeg = composeLocalStripSheetJpegForTest(
        sourceBytes: [
          _solidJpeg(220, 20, 20),
          _solidJpeg(20, 220, 20),
          _solidJpeg(20, 20, 220),
        ],
        filterId: 'clean',
        frameId: 'f3:dps-1',
        single: false,
        overlay: LocalStripOverlay(
          pngBytes: _overlayPng(
            width: 60,
            height: 180,
            holeLeft: 5,
            holeTop: 29,
            holeWidth: 50,
            holeHeight: 38,
          ),
          slots: defaultOccasionStripSlots(3),
        ),
      );
      expect(jpeg, isNotEmpty);
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
    final letterbox = wide.getPixel(2, 2);
    expect(letterbox.r, greaterThan(240));
    expect(letterbox.g, greaterThan(240));
    final plate = wide.getPixel(20, 20);
    expect(plate.b, greaterThan(plate.r));
    final custom = prepareLocalStripCellForTest(
      _solidJpeg(10, 20, 30, width: 80, height: 20),
      40,
      40,
      contain: true,
      letterbox: img.ColorRgb8(0, 0, 0),
    );
    expect(custom!.getPixel(1, 1).r, lessThan(20));

    final tall = prepareLocalStripCellForTest(
      _solidJpeg(30, 20, 10, width: 20, height: 80),
      40,
      40,
      matrix: List<double>.filled(20, 0),
      contain: true,
    );
    expect(tall, isNotNull);
    expect(tall!.width, 40);

    final cover = prepareLocalStripCellForTest(
      _solidJpeg(20, 20, 220, width: 80, height: 20),
      40,
      40,
      contain: false,
    );
    expect(cover, isNotNull);
    expect(cover!.width, 40);
    final filled = cover.getPixel(2, 2);
    expect(filled.b, greaterThan(150));

    final coverTall = prepareLocalStripCellForTest(
      _solidJpeg(220, 20, 20, width: 20, height: 80),
      40,
      40,
      contain: false,
    );
    expect(coverTall, isNotNull);
    expect(coverTall!.height, 40);
  });

  test('cover-fit fills tall classic cells instead of letterboxing', () {
    final jpeg = composeLocalStripSheetJpegForTest(
      sourceBytes: [
        _solidJpeg(220, 20, 20, width: 80, height: 20),
        _solidJpeg(20, 220, 20, width: 80, height: 20),
        _solidJpeg(20, 20, 220, width: 80, height: 20),
      ],
      filterId: 'clean',
      frameId: 'classic',
      single: false,
    );
    final decoded = img.decodeJpg(jpeg)!;
    const stripDrawWidth =
        (kLocalStripSheetWidth - kLocalStripCenterGutter) ~/ 2;
    const cellWidth = stripDrawWidth - kLocalStripBorder * 2;
    final x = kLocalStripBorder + cellWidth ~/ 2;
    final filled = decoded.getPixel(x, kLocalStripBorderTop + 8);
    expect(filled.r, greaterThan(filled.g));
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

Uint8List _overlayPng({
  required int width,
  required int height,
  required int holeLeft,
  required int holeTop,
  required int holeWidth,
  required int holeHeight,
}) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final inHole = x >= holeLeft &&
          x < holeLeft + holeWidth &&
          y >= holeTop &&
          y < holeTop + holeHeight;
      image.setPixelRgba(
        x,
        y,
        0,
        inHole ? 0 : 180,
        inHole ? 0 : 40,
        inHole ? 0 : 255,
      );
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}
