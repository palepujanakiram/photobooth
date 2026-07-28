import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/strip_models.dart';
import 'package:photobooth/utils/constants.dart';

void main() {
  test('kStripCellAspectRatio matches 2×6 print cell geometry', () {
    expect(kStripCellAspectRatio, closeTo(592 / 448, 0.0001));
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
        'confetti',
        'stars',
        'flowers',
      ]),
    );
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
    expect(catalog.wysiwyg.borderRatio, closeTo(4 / 600, 0.0001));
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

  test('StripComposeResult prefers stripCompositeUrl for print', () {
    final result = StripComposeResult.fromJson({
      'imageUrl': 'https://example.com/a.jpg',
      'stripCompositeUrl': 'https://example.com/b.jpg',
      'filter': 'candy_pop',
      'frame': 'noir',
      'sticker': 'sparkles',
      'width': 1200,
      'height': 1800,
      'copiesOnSheet': 2,
      'printSize': 's4x6',
      'runId': 'run-strip-1',
    });
    expect(result.printImageUrl, 'https://example.com/b.jpg');
    expect(result.filter, 'candy_pop');
    expect(result.frame, 'noir');
    expect(result.sticker, 'sparkles');
    expect(result.width, 1200);
    expect(result.height, 1800);
    expect(result.runId, 'run-strip-1');
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
