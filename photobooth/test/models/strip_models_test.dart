import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/strip_models.dart';
import 'package:photobooth/utils/constants.dart';

void main() {
  test('kStripCellAspectRatio matches 2×6 print cell geometry', () {
    expect(kStripCellAspectRatio, closeTo(580 / 437.5, 0.0001));
    expect(kStripCellAspectRatio, greaterThan(1)); // wider than tall
  });

  test('StripScribbleStroke serializes for compose API', () {
    const stroke = StripScribbleStroke(
      color: '#FFFFFF',
      width: 0.02,
      points: [
        StripScribblePoint(0.1, 0.2),
        StripScribblePoint(0.3, 0.4),
      ],
    );
    expect(stroke.toJson(), {
      'color': '#FFFFFF',
      'width': 0.02,
      'points': [
        {'x': 0.1, 'y': 0.2},
        {'x': 0.3, 'y': 0.4},
      ],
    });
    expect(kStripScribblePenColors, contains('#FF4D6D'));
  });

  test('StripStickerPlacement serializes for compose API', () {
    const p = StripStickerPlacement(
      id: 's1',
      type: 'hearts',
      x: 0.4,
      y: 0.6,
      scale: 1.25,
    );
    expect(p.toJson(), {
      'type': 'hearts',
      'x': 0.4,
      'y': 0.6,
      'scale': 1.25,
    });
    expect(p.copyWith(x: 0.1).x, 0.1);
    expect(p.copyWith(y: 0.2, scale: 2).scale, 2);
    expect(
      kPlaceableStripStickerIds,
      containsAll([
        'hearts',
        'sparkles',
        'stars',
        'flowers',
      ]),
    );
    expect(kPlaceableStripStickerIds, isNot(contains('confetti')));
    expect(kPlaceableStripStickerIds, isNot(contains('bows')));
    expect(kPlaceableStripStickerIds, isNot(contains('butterflies')));
    expect(kPlaceableStripStickerIds, isNot(contains('petals')));
    expect(kPlaceableStripStickerIds, isNot(contains('date')));
  });

  test('StripFiltersCatalog.fromJson parses catalog and print hints', () {
    final catalog = StripFiltersCatalog.fromJson({
      'brand': 'FotoFlashback',
      'shotCount': 4,
      'filters': [
        {
          'id': 'classic_warm',
          'name': 'Classic Warm',
          'description': 'Warm',
          'cssFilter': 'sepia(0.28)',
        },
        {
          'id': 'mono',
          'name': 'Noir',
          'description': 'B&W',
          'cssFilter': 'grayscale(1)',
        },
      ],
      'frames': [
        {'id': 'noir', 'name': 'Noir Matte', 'description': 'Dark'},
      ],
      'stickers': [
        {'id': 'hearts', 'name': 'Hearts', 'description': 'Hearts'},
      ],
      'print': {
        'size': 's4x6',
        'copiesOnSheet': 2,
        'note': 'Two strips',
      },
    });

    expect(catalog.brand, 'FotoFlashback');
    expect(catalog.shotCount, 4);
    expect(catalog.filters, hasLength(2));
    expect(catalog.filters.first.id, 'classic_warm');
    expect(catalog.frames.single.id, 'noir');
    expect(catalog.stickers.single.id, 'hearts');
    expect(catalog.printSize, 's4x6');
    expect(catalog.copiesOnSheet, 2);
    expect(catalog.printNote, 'Two strips');
    expect(catalog.wysiwyg.borderRatio, closeTo(10 / 600, 0.0001));
  });

  test('StripWysiwygLayout.fromJson parses romantic slots', () {
    final layout = StripWysiwygLayout.fromJson({
      'strip': {'borderRatio': 4 / 600},
      'romantic': {
        'slots': [
          {'left': 0.1, 'top': 0.2, 'width': 0.3, 'height': 0.4},
          {'left': 0.1, 'top': 0.2, 'width': 0.3, 'height': 0.4},
          {'left': 0.1, 'top': 0.2, 'width': 0.3, 'height': 0.4},
          {'left': 0.1, 'top': 0.2, 'width': 0.3, 'height': 0.4},
        ],
        'caption': 'Hello',
      },
    });
    expect(layout.romanticSlots, hasLength(4));
    expect(layout.romanticSlots.first.left, 0.1);
    expect(layout.romanticCaption, 'Hello');
  });

  test('StripFiltersCatalog.fromJson uses defaults and Map casts', () {
    final catalog = StripFiltersCatalog.fromJson({
      'filters': [
        <dynamic, dynamic>{
          'id': 'clean',
          'name': 'Clean',
          'description': 'Plain',
        },
        'skip-me',
      ],
      'print': <dynamic, dynamic>{
        'size': 's4x6',
        'copiesOnSheet': 2,
      },
    });
    expect(catalog.brand, 'FotoFlashback');
    expect(catalog.shotCount, kStripShotCount);
    expect(catalog.filters, hasLength(1));
    expect(catalog.filters.single.cssFilter, 'none');
    expect(catalog.printNote, isNull);

    final empty = StripFiltersCatalog.fromJson(const {});
    expect(empty.filters, isEmpty);
    expect(empty.printSize, AppConstants.kPrintSizeStripDual2x6);
    expect(empty.copiesOnSheet, 2);
  });

  test('StripComposeResult prefers stripCompositeUrl for dual strip', () {
    final result = StripComposeResult.fromJson({
      'imageUrl': 'https://example.com/a.jpg',
      'stripCompositeUrl': 'https://example.com/b.jpg',
      'filter': 'candy_pop',
      'frame': 'noir',
      'sticker': 'sparkles',
      'width': 1200,
      'height': 1800,
      'copiesOnSheet': 2,
      'printSize': 's6x2_2',
      'runId': 'run-strip-1',
    });
    expect(result.printImageUrl, 'https://example.com/b.jpg');
    expect(result.singleStripPreviewUrl, 'https://example.com/a.jpg');
    expect(result.filter, 'candy_pop');
    expect(result.frame, 'noir');
    expect(result.sticker, 'sparkles');
    expect(result.width, 1200);
    expect(result.height, 1800);
    expect(result.runId, 'run-strip-1');
  });

  test('StripComposeResult single 6×4 uses imageUrl not composite', () {
    final result = StripComposeResult.fromJson(
      {
        'imageUrl': 'https://example.com/single6x4.jpg',
        'stripCompositeUrl': 'https://example.com/dual-strip.jpg',
        'filter': 'classic_warm',
        'printSize': 's6x2_2',
        'copiesOnSheet': 2,
        'width': 1800,
        'height': 1200,
      },
      composeImageCount: 1,
    );
    expect(result.printSize, AppConstants.kPrintSizeLandscape6x4);
    expect(result.copiesOnSheet, 1);
    expect(result.printImageUrl, 'https://example.com/single6x4.jpg');
    expect(result.imageUrl, 'https://example.com/single6x4.jpg');
  });

  test('StripComposeResult single shot keeps API portrait s4x6', () {
    final result = StripComposeResult.fromJson(
      {
        'imageUrl': 'https://example.com/single4x6.jpg',
        'stripCompositeUrl': 'https://example.com/dual-strip.jpg',
        'filter': 'classic_warm',
        'printSize': 's4x6',
        'copiesOnSheet': 1,
        'width': 1200,
        'height': 1800,
      },
      composeImageCount: 1,
    );
    expect(result.printSize, AppConstants.kPrintSizePortrait4x6);
    expect(result.printImageUrl, 'https://example.com/single4x6.jpg');
  });

  test('StripComposeResult portrait s4x6 uses imageUrl not composite', () {
    final result = StripComposeResult.fromJson({
      'imageUrl': 'https://example.com/a.jpg',
      'stripCompositeUrl': 'https://example.com/b.jpg',
      'filter': 'candy_pop',
      'printSize': 's4x6',
      'copiesOnSheet': 1,
    });
    expect(result.printImageUrl, 'https://example.com/a.jpg');
  });

  test('StripComposeResult falls back to imageUrl', () {
    final result = StripComposeResult.fromJson({
      'imageUrl': 'https://example.com/a.jpg',
      'filter': 'clean',
    });
    expect(result.printImageUrl, 'https://example.com/a.jpg');
    expect(result.filter, 'clean');
  });

  test('StripComposeResult uses stripCompositeUrl when imageUrl missing', () {
    final result = StripComposeResult.fromJson({
      'stripCompositeUrl': 'https://example.com/c.jpg',
    });
    expect(result.imageUrl, 'https://example.com/c.jpg');
    expect(result.printImageUrl, 'https://example.com/c.jpg');
    expect(result.filter, kDefaultStripFilterId);

    final blankComposite = StripComposeResult(
      imageUrl: 'https://example.com/a.jpg',
      filter: 'clean',
      stripCompositeUrl: '   ',
    );
    expect(blankComposite.printImageUrl, 'https://example.com/a.jpg');
  });

  test('StripWysiwygLayout.fromJson parses grid and film labels', () {
    final layout = StripWysiwygLayout.fromJson({
      'grid2x2': {
        'title': 'Together Now',
        'subtitle': 'Best day ever',
      },
      'filmstrip': {'label': 'ROLL A'},
    });
    expect(layout.gridTitle, 'Together Now');
    expect(layout.gridSubtitle, 'Best day ever');
    expect(layout.filmLabel, 'ROLL A');
  });

  test('StripWysiwygLayout falls back on invalid slot maps', () {
    final layout = StripWysiwygLayout.fromJson({
      'romantic': {
        'slots': [
          {'left': 0.1, 'top': 0.2, 'width': 0.3, 'height': 0.4},
          {'left': 0.1, 'top': 0.2, 'width': 0.3, 'height': 0.4},
          {'left': 0.1, 'top': 0.2, 'width': 0.3, 'height': 0.4},
          'not-a-map',
        ],
      },
      'polaroid': {
        'slots': [
          {'left': 0.1, 'top': 0.2, 'rotDeg': 1},
          {'left': 0.1, 'top': 0.2, 'rotDeg': 1},
          {'left': 0.1, 'top': 0.2, 'rotDeg': 1},
          null,
        ],
      },
    });
    expect(layout.romanticSlots, StripWysiwygLayout.defaults.romanticSlots);
    expect(layout.polaroidSlots, StripWysiwygLayout.defaults.polaroidSlots);
  });

  test('StripFiltersCatalog.fromJson coerces nested Map types', () {
    final catalog = StripFiltersCatalog.fromJson({
      'brand': 'FotoFlashback',
      'shotCount': 4,
      'filters': [
        {
          'id': 'classic_warm',
          'name': 'Classic Warm',
          'description': 'Warm',
          'cssFilter': 'none',
        },
      ],
      'print': {
        'size': 's6x2_2',
        'copiesOnSheet': 2,
        'note': 'Two strips',
      },
      'layout': {
        'grid2x2': {'title': 'Grid title'},
      },
      'features': {
        'enableSurpriseMeAi': true,
        'enableOsdScrub': true,
      },
    });
    expect(catalog.printNote, 'Two strips');
    expect(catalog.enableSurpriseMeAi, isTrue);
    expect(catalog.enableOsdScrub, isTrue);
    expect(catalog.wysiwyg.gridTitle, 'Grid title');
  });

  test('StripFiltersCatalog.fromJson coerces loosely typed maps', () {
    final catalog = StripFiltersCatalog.fromJson({
      'brand': 'FotoFlashback',
      'shotCount': 4,
      'filters': [
        {
          'id': 'classic_warm',
          'name': 'Classic Warm',
          'description': 'Warm',
          'cssFilter': 'none',
        },
      ],
      'layout': <Object, Object?>{'grid2x2': <Object, Object?>{'title': 'Loose'}},
      'features': <Object, Object?>{'enableSurpriseMeAi': true},
    });
    expect(catalog.enableSurpriseMeAi, isTrue);
    expect(catalog.wysiwyg.gridTitle, 'Loose');
  });

  test('StripComposeResult uses composite when imageUrl blank on single sheet',
      () {
    final result = StripComposeResult(
      imageUrl: '   ',
      filter: 'clean',
      stripCompositeUrl: 'https://example.com/composite.jpg',
      printSize: AppConstants.kPrintSizeLandscape6x4,
    );
    expect(result.printImageUrl, 'https://example.com/composite.jpg');
  });

  test('StripFrame parses admin template fields', () {
    final frame = StripFrame.fromJson({
      'id': 'st:abc',
      'name': 'Date night',
      'description': 'Scrapbook',
      'kind': 'template',
      'overlayUrl': 'https://example.com/o.png',
      'caption': 'Date night',
      'logoUrl': 'https://example.com/l.png',
    });
    expect(frame.isTemplate, isTrue);
    expect(isStripTemplateFrame(frame.id), isTrue);
    expect(frame.overlayUrl, 'https://example.com/o.png');
    expect(frame.caption, 'Date night');
    expect(isStripSheetLayout(frame.id), isFalse);
  });
}
