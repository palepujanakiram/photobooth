import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/strip_models.dart';
import 'package:photobooth/utils/constants.dart';

void main() {
  test('kStripCellAspectRatio matches 2×6 print cell geometry', () {
    expect(kStripCellAspectRatio, closeTo(564 / 432, 0.0001));
    expect(kStripCellAspectRatio, greaterThan(1)); // wider than tall
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
    expect(catalog.printSize, 's4x6');
    expect(catalog.copiesOnSheet, 2);
    expect(catalog.printNote, 'Two strips');
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
      'width': 1200,
      'height': 1800,
      'copiesOnSheet': 2,
      'printSize': 's4x6',
    });
    expect(result.printImageUrl, 'https://example.com/b.jpg');
    expect(result.filter, 'candy_pop');
    expect(result.width, 1200);
    expect(result.height, 1800);
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
}
