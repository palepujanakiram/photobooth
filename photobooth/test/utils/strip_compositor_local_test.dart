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

      // Sample cell centers — 3-shot windows cover-fill landscape plates.
      const cellHeight = (kLocalStripSheetHeight -
              kLocalStripBorderTop -
              kLocalStripBorderBottom -
              kLocalStripGutter * 2) ~/
          3;
      final firstCell = decoded.getPixel(
        300,
        kLocalStripBorderTop + cellHeight ~/ 2,
      );
      final firstCellTop = decoded.getPixel(
        300,
        kLocalStripBorderTop + 8,
      );
      expect(firstCellTop.r, greaterThan(180));
      final secondCell = decoded.getPixel(
        300,
        kLocalStripBorderTop + cellHeight + kLocalStripGutter + cellHeight ~/ 2,
      );
      final thirdCell = decoded.getPixel(
        300,
        kLocalStripBorderTop +
            (cellHeight + kLocalStripGutter) * 2 +
            cellHeight ~/ 2,
      );
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

    test('composes from preloaded jpeg bytes without source URLs', () async {
      final jpeg = await composeLocalStripSheet(
        LocalStripComposeRequest(
          sources: const [],
          jpegBytes: [_solidJpeg(40, 80, 160)],
          filterId: 'clean',
          frameId: 'classic',
          single: true,
          orientation: PrintOrientation.portrait,
        ),
      );
      expect(jpeg, isNotNull);
      expect(jpeg, isNotEmpty);
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

    test('contain-fits a portrait capture in a landscape 6x4 hole', () {
      final overlay = _overlayPng(
        width: 180,
        height: 120,
        holeLeft: 8,
        holeTop: 8,
        holeWidth: 164,
        holeHeight: 90,
      );
      final jpeg = composeLocalStripSheetJpegForTest(
        sourceBytes: [_markerHeadJpeg()],
        filterId: 'clean',
        frameId: 'ai:dps-1',
        single: true,
        landscape: true,
        overlay: LocalStripOverlay(
          pngBytes: overlay,
          slots: const [
            StripTemplateSlot(left: 8 / 180, top: 8 / 120, width: 164 / 180, height: 90 / 120),
          ],
        ),
      );
      final decoded = img.decodeJpg(jpeg)!;
      expect(decoded.width, kLocalStripSheetHeight);
      expect(decoded.height, kLocalStripSheetWidth);
      final holeLeft = 8 / 180 * decoded.width;
      final holeTop = 8 / 120 * decoded.height;
      final holeW = 164 / 180 * decoded.width;
      final holeH = 90 / 120 * decoded.height;
      final hx = (holeLeft + holeW / 2).round();
      final head = decoded.getPixel(hx, (holeTop + holeH * 0.12).round());
      expect(head.g, greaterThan(150));
      expect(head.b, lessThan(100));
      final mid = decoded.getPixel(hx, (holeTop + holeH * 0.5).round());
      expect(mid.b, greaterThan(150));
      expect(mid.g, lessThan(80));
    });

    test('fills 6x4 occasion chrome on a landscape sheet', () {
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
      expect(edge.g, greaterThan(edge.r));
      final hole = defaultOccasionSinglePhotoHole;
      final photo = decoded.getPixel(
        (hole.left * decoded.width + hole.width * decoded.width / 2).round(),
        (hole.top * decoded.height + hole.height * decoded.height / 2).round(),
      );
      expect(photo.r, greaterThan(photo.g));
    });

    test('reports overlay dest size for 1-shot and dual-strip', () {
      expect(
        localStripOverlayDestSize(single: true, landscape: false),
        (width: kLocalStripSheetWidth, height: kLocalStripSheetHeight),
      );
      expect(
        localStripOverlayDestSize(single: true, landscape: true),
        (width: kLocalStripSheetHeight, height: kLocalStripSheetWidth),
      );
      expect(
        localStripOverlayDestSize(single: false, landscape: false).width,
        (kLocalStripSheetWidth - kLocalStripCenterGutter) ~/ 2,
      );
      expect(kLocalPrintJpegMaxLongEdge, kLocalStripSheetHeight);
      expect(kLocalStripCellJpegMaxLongEdge, 720);
      expect(
        localStripPrintJpegMaxLongEdge(single: true),
        kLocalPrintJpegMaxLongEdge,
      );
      expect(
        localStripPrintJpegMaxLongEdge(single: false),
        kLocalStripCellJpegMaxLongEdge,
      );
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
      final first = decoded.getPixel(296, 428);
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

    final matched = prepareLocalStripCellForTest(
      _solidJpeg(20, 20, 220, width: 80, height: 20),
      80,
      20,
      contain: false,
    );
    expect(matched!.width, 80);
    expect(matched.height, 20);
  });

  test('cover-fill centers a landscape webcam in a wide 3/4-shot hole', () {
    final webcam = _bandedJpeg(width: 160, height: 90);
    final cell = prepareLocalStripCellForTest(webcam, 80, 20, contain: false)!;
    expect(cell.width, 80);
    expect(cell.height, 20);
    final subject = cell.getPixel(40, 10);
    expect(subject.r, greaterThan(150));
    expect(subject.g, lessThan(80));
  });

  test('cover-fill keeps heads of a portrait still in a landscape hole', () {
    final portrait = _markerHeadJpeg(width: 40, height: 80);
    final cell = prepareLocalStripCellForTest(portrait, 80, 20, contain: false)!;
    final top = cell.getPixel(40, 2);
    expect(top.g, greaterThan(150));
    expect(top.b, lessThan(100));
  });

  test('3-shot and 4-shot occasion strips center a landscape webcam', () {
    for (final shotCount in [3, 4]) {
      final slots = [
        for (var i = 0; i < shotCount; i++)
          StripTemplateSlot(
            left: 0.08,
            top: 0.16 + i * 0.18,
            width: 0.84,
            height: 0.12,
          ),
      ];
      final jpeg = composeLocalStripSheetJpegForTest(
        sourceBytes: List<Uint8List>.generate(
          shotCount,
          (_) => _bandedJpeg(),
        ),
        filterId: 'clean',
        frameId: shotCount == 3 ? 'f3:dps-1' : 'fr:dps-1',
        single: false,
        overlay: LocalStripOverlay(
          pngBytes: _overlayPng(
            width: 60,
            height: 180,
            holeLeft: 5,
            holeTop: 29,
            holeWidth: 50,
            holeHeight: 22,
          ),
          slots: slots,
        ),
      );
      final decoded = img.decodeJpg(jpeg)!;
      const stripW = (kLocalStripSheetWidth - kLocalStripCenterGutter) ~/ 2;
      final cell = slots.first;
      final cx = (cell.left * stripW + cell.width * stripW / 2).round();
      final cy = (cell.top * kLocalStripSheetHeight +
              cell.height * kLocalStripSheetHeight / 2)
          .round();
      final pixel = decoded.getPixel(cx, cy);
      expect(pixel.r, greaterThan(150), reason: '$shotCount-shot subject');
    }
  });

  test('1-shot occasion contain-fits a landscape capture in a portrait hole', () {
    const holeLeft = 9;
    const holeTop = 32;
    const holeWidth = 102;
    const holeHeight = 108;
    final overlay = _overlayPng(
      width: 120,
      height: 180,
      holeLeft: holeLeft,
      holeTop: holeTop,
      holeWidth: holeWidth,
      holeHeight: holeHeight,
    );
    final jpeg = composeLocalStripSheetJpegForTest(
      sourceBytes: [_solidJpeg(220, 20, 20, width: 80, height: 20)],
      filterId: 'clean',
      frameId: 'ai:dps-1',
      single: true,
      overlay: LocalStripOverlay(
        pngBytes: overlay,
        slots: const [
          StripTemplateSlot(
            left: holeLeft / 120,
            top: holeTop / 180,
            width: holeWidth / 120,
            height: holeHeight / 180,
          ),
        ],
      ),
    );
    final decoded = img.decodeJpg(jpeg)!;
    int sample(double nx, double ny) {
      final pixel = decoded.getPixel(
        (nx * decoded.width).round().clamp(0, decoded.width - 1),
        (ny * decoded.height).round().clamp(0, decoded.height - 1),
      );
      return pixel.r.toInt();
    }

    const holeMidX = (holeLeft + holeWidth / 2) / 120;
    // Landscape still letterboxes the top of a tall hole instead of cropping.
    expect(sample(holeMidX, (holeTop + 8) / 180), lessThan(80));
    expect(
      sample(holeMidX, (holeTop + holeHeight / 2) / 180),
      greaterThan(150),
    );
  });

  test('Classic 1-shot contain-fits a landscape capture on 4x6', () {
    final jpeg = composeLocalStripSheetJpegForTest(
      sourceBytes: [_solidJpeg(20, 200, 20, width: 80, height: 20)],
      filterId: 'clean',
      frameId: 'classic',
      single: true,
    );
    final decoded = img.decodeJpg(jpeg)!;
    expect(decoded.width, kLocalStripSheetWidth);
    expect(decoded.height, kLocalStripSheetHeight);
    final margin =
        (kLocalStripSheetWidth * kClassicSingleMatteRatio).round();
    final above = decoded.getPixel(kLocalStripSheetWidth ~/ 2, margin + 8);
    expect(above.r, greaterThan(240));
    final plate = decoded.getPixel(
      kLocalStripSheetWidth ~/ 2,
      kLocalStripSheetHeight ~/ 2,
    );
    expect(plate.g, greaterThan(150));
  });

  test('Classic 1-shot landscape keeps chrome in the matte around the photo', () {
    final jpeg = composeLocalStripSheetJpegForTest(
      sourceBytes: [_solidJpeg(20, 200, 20, width: 80, height: 20)],
      filterId: 'clean',
      frameId: 'classic',
      single: true,
      landscape: true,
    );
    final decoded = img.decodeJpg(jpeg)!;
    expect(decoded.width, kLocalStripSheetHeight);
    expect(decoded.height, kLocalStripSheetWidth);
    final hole = classicChromeSinglePhotoHole();
    final matteY = (hole.top * decoded.height * 0.4).round();
    final matte = decoded.getPixel(decoded.width ~/ 2, matteY);
    expect(matte.r, greaterThan(240));
    final photo = decoded.getPixel(
      (hole.left * decoded.width + hole.width * decoded.width / 2).round(),
      (hole.top * decoded.height + hole.height * decoded.height / 2).round(),
    );
    expect(photo.g, greaterThan(150));
  });

  test('landscape plates contain-fit 3-shot and 4-shot classic cells', () {
    for (final shotCount in [kStripShotCountThree, kStripShotCount]) {
      _expectLandscapeContainInClassicCells(shotCount);
    }
  });

  test('Classic 3-shot contain-fits a portrait capture from head to body', () {
    final jpeg = composeLocalStripSheetJpegForTest(
      sourceBytes: [
        _markerHeadJpeg(width: 40, height: 80),
        _markerHeadJpeg(width: 40, height: 80),
        _markerHeadJpeg(width: 40, height: 80),
      ],
      filterId: 'clean',
      frameId: 'classic',
      single: false,
    );
    final decoded = img.decodeJpg(jpeg)!;
    const stripDrawWidth =
        (kLocalStripSheetWidth - kLocalStripCenterGutter) ~/ 2;
    const cellWidth = stripDrawWidth - kLocalStripBorder * 2;
    final innerHeight = kLocalStripSheetHeight -
        kLocalStripBorderTop -
        kLocalStripBorderBottom -
        kLocalStripGutter * 2;
    final cellHeight = innerHeight ~/ 3;
    final x = kLocalStripBorder + cellWidth ~/ 2;
    final head = decoded.getPixel(x, kLocalStripBorderTop + 12);
    expect(head.g, greaterThan(150));
    expect(head.b, lessThan(100));
    final body = decoded.getPixel(
      x,
      kLocalStripBorderTop + cellHeight - 12,
    );
    expect(body.b, greaterThan(150));
    expect(body.g, lessThan(100));
  });
}

void _expectLandscapeContainInClassicCells(int shotCount) {
  final sourceBytes = [
    _solidJpeg(220, 20, 20, width: 80, height: 20),
    _solidJpeg(20, 220, 20, width: 80, height: 20),
    _solidJpeg(20, 20, 220, width: 80, height: 20),
    if (shotCount >= kStripShotCount)
      _solidJpeg(220, 180, 20, width: 80, height: 20),
  ];
  final jpeg = composeLocalStripSheetJpegForTest(
    sourceBytes: sourceBytes,
    filterId: 'clean',
    frameId: 'classic',
    single: false,
  );
  final decoded = img.decodeJpg(jpeg)!;
  const stripDrawWidth =
      (kLocalStripSheetWidth - kLocalStripCenterGutter) ~/ 2;
  const cellWidth = stripDrawWidth - kLocalStripBorder * 2;
  final innerHeight = kLocalStripSheetHeight -
      kLocalStripBorderTop -
      kLocalStripBorderBottom -
      kLocalStripGutter * (shotCount - 1);
  final cellHeight = innerHeight ~/ shotCount;
  final x = kLocalStripBorder + cellWidth ~/ 2;
  final edge = decoded.getPixel(x, kLocalStripBorderTop + 8);
  expect(edge.r, greaterThan(180), reason: '$shotCount-shot letterbox');
  expect(edge.g, greaterThan(180), reason: '$shotCount-shot letterbox');
  final plate = decoded.getPixel(
    x,
    kLocalStripBorderTop + cellHeight ~/ 2,
  );
  expect(plate.r, greaterThan(180), reason: '$shotCount-shot plate');
  expect(plate.g, lessThan(80), reason: '$shotCount-shot plate');
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

/// Portrait capture: green head band on top, blue body below.
Uint8List _markerHeadJpeg({int width = 60, int height = 90}) {
  final image = img.Image(width: width, height: height);
  final headEnd = height ~/ 3;
  for (var y = 0; y < height; y++) {
    final head = y < headEnd;
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(
        x,
        y,
        head ? 40 : 20,
        head ? 220 : 20,
        head ? 60 : 200,
      );
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

/// Landscape webcam: green ceiling, red subject, blue floor.
Uint8List _bandedJpeg({int width = 160, int height = 90}) {
  final image = img.Image(width: width, height: height);
  final third = height ~/ 3;
  for (var y = 0; y < height; y++) {
    final band = y < third ? 0 : (y < third * 2 ? 1 : 2);
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(
        x,
        y,
        band == 1 ? 220 : 20,
        band == 0 ? 220 : 20,
        band == 2 ? 220 : 20,
      );
    }
  }
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
