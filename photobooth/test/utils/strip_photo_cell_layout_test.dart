import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/strip_models.dart';
import 'package:photobooth/utils/strip_photo_cell_layout.dart';

void main() {
  const stripW = 600.0;
  const stripH = 1800.0;

  group('computeStripPhotoCellRects classic', () {
    test('matches HAMA-style equal margins and gutters on 600×1800', () {
      final cells = computeStripPhotoCellRects(
        frameId: 'classic',
        stripWidth: stripW,
        stripHeight: stripH,
      );
      expect(cells, hasLength(kStripShotCount));
      expect(cells.first.width, closeTo(580, 0.01));
      expect(cells.first.height, closeTo(1750 / 4, 0.01));
      expect(cells.first.left, closeTo(10, 0.01));
      expect(cells.first.top, closeTo(10, 0.01));
      expect(cells[1].top, closeTo(10 + 1750 / 4 + 10, 0.01));
    });

    test('3-shot uses taller cells with the same gutters', () {
      final cells = computeStripPhotoCellRects(
        frameId: 'classic',
        stripWidth: stripW,
        stripHeight: stripH,
        shotCount: 3,
      );
      expect(cells, hasLength(3));
      // (1800 - 10 - 10 - 2*10) / 3 = 1760/3
      expect(cells.first.height, closeTo(1760 / 3, 0.01));
      expect(cells.first.width, closeTo(580, 0.01));
    });
  });

  group('computeStripPhotoCellRects filmstrip', () {
    test('uses rails and HAMA-aligned vertical stack', () {
      final layout = StripWysiwygLayout.defaults;
      final cells = computeStripPhotoCellRects(
        frameId: 'filmstrip',
        stripWidth: stripW,
        stripHeight: stripH,
        layout: layout,
      );
      final rail = stripW * (36 / 600);
      final marginY = stripH * layout.filmMarginY;
      final gutter = stripH * layout.filmGutter;
      final bottom = stripH * layout.borderBottomRatio;
      final cellW = stripW - 2 * rail;
      final cellH =
          (stripH - marginY - bottom - (kStripShotCount - 1) * gutter) /
              kStripShotCount;

      expect(cells.first.left, closeTo(rail, 0.01));
      expect(cells.first.top, closeTo(marginY, 0.01));
      expect(cells.first.width, closeTo(cellW, 0.01));
      expect(cells.first.height, closeTo(cellH, 0.01));
      expect(cells[1].top, closeTo(marginY + cellH + gutter, 0.01));
      expect(stripPhotoCellUsesContainFit('filmstrip'), isFalse);
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
        closeTo(36, 0.01),
      );
      expect(
        stripChromeBorderPad(
          frameId: 'classic',
          stripWidth: stripW,
        ),
        closeTo(10, 0.01),
      );
    });
  });
}
