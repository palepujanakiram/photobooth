import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/strip_models.dart';
import 'package:photobooth/utils/strip_photo_cell_layout.dart';

void main() {
  const stripW = 600.0;
  const stripH = 1800.0;

  group('computeStripPhotoCellRects classic', () {
    test('matches zenai 592×448 cover cells on 600×1800', () {
      final cells = computeStripPhotoCellRects(
        frameId: 'classic',
        stripWidth: stripW,
        stripHeight: stripH,
      );
      expect(cells, hasLength(kStripShotCount));
      expect(cells.first.width, closeTo(592, 0.01));
      expect(cells.first.height, closeTo(448, 0.01));
      expect(cells.first.left, closeTo(4, 0.01));
      expect(cells.first.top, closeTo(4, 0.01));
      expect(cells.last.top, closeTo(4 + 3 * 448, 0.01));
    });
  });

  group('computeStripPhotoCellRects filmstrip', () {
    test('uses rails, marginY, and gutters from layout', () {
      final layout = StripWysiwygLayout.defaults;
      final cells = computeStripPhotoCellRects(
        frameId: 'filmstrip',
        stripWidth: stripW,
        stripHeight: stripH,
        layout: layout,
      );
      final rail = stripW * (52 / 600);
      final marginY = stripH * layout.filmMarginY;
      final gutter = stripH * layout.filmGutter;
      final cellW = stripW - 2 * rail;
      final cellH =
          (stripH - 2 * marginY - (kStripShotCount - 1) * gutter) /
              kStripShotCount;

      expect(cells.first.left, closeTo(rail, 0.01));
      expect(cells.first.top, closeTo(marginY, 0.01));
      expect(cells.first.width, closeTo(cellW, 0.01));
      expect(cells.first.height, closeTo(cellH, 0.01));
      expect(cells[1].top, closeTo(marginY + cellH + gutter, 0.01));
      expect(stripPhotoCellUsesContainFit('filmstrip'), isTrue);
      expect(
        stripPhotoCellLetterboxColor('filmstrip'),
        const Color(0xFF0A0A0A),
      );
    });
  });

  group('stripChromeBorderPad', () {
    test('filmstrip uses rail width not uniform border', () {
      expect(
        stripChromeBorderPad(
          frameId: 'filmstrip',
          stripWidth: stripW,
        ),
        closeTo(52, 0.01),
      );
      expect(
        stripChromeBorderPad(
          frameId: 'classic',
          stripWidth: stripW,
        ),
        closeTo(4, 0.01),
      );
    });
  });
}
