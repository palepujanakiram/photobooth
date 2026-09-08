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
        shotCount: kStripShotCountThree,
      );
      expect(cells, hasLength(3));
      // (1800 - 10 - 10 - 2*10) / 3 = 1760/3
      expect(cells.first.height, closeTo(1760 / 3, 0.01));
      expect(cells.first.width, closeTo(580, 0.01));
      expect(cells.first.top, closeTo(10, 0.01));
      expect(
        cells.last.top + cells.last.height,
        closeTo(stripH - 10, 0.01),
      );
    });

    test('an unusable shot count falls back to the four-shot strip', () {
      final cells = computeStripPhotoCellRects(
        frameId: 'classic',
        stripWidth: stripW,
        stripHeight: stripH,
        shotCount: 0,
      );
      expect(cells, hasLength(kStripShotCount));
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
      expect(stripPhotoCellUsesContainFit('classic'), isFalse);
      expect(
        stripPhotoCellUsesContainFit('classic', shotCount: kStripShotCountThree),
        isFalse,
      );
      expect(
        stripPhotoCellUsesContainFit('f3:dps', shotCount: kStripShotCountThree),
        isFalse,
      );
      expect(
        stripPhotoCellUsesContainFit('fr:dps', shotCount: kStripShotCount),
        isFalse,
      );
      expect(
        stripPhotoCellUsesContainFit('classic', shotCount: 1),
        isTrue,
      );
      expect(
        stripPhotoCellUsesContainFit('filmstrip', shotCount: 1),
        isTrue,
      );
      expect(
        stripPhotoCellUsesContainFit('ai:dps', shotCount: 1),
        isTrue,
      );
      expect(
        stripPhotoCellUsesContainFit('classic', shotCount: 0),
        isFalse,
      );
      expect(stripPhotoCellUsesContainFit('polaroid'), isFalse);
      expect(stripPhotoCellUsesContainFit(''), isFalse);

      final threeCells = computeStripPhotoCellRects(
        frameId: 'filmstrip',
        stripWidth: stripW,
        stripHeight: stripH,
        shotCount: kStripShotCountThree,
        layout: layout,
      );
      final threeCellH =
          (stripH - marginY - bottom - 2 * gutter) / 3;
      expect(threeCells, hasLength(3));
      expect(threeCells.first.height, closeTo(threeCellH, 0.01));
      expect(threeCells.first.width, closeTo(cellW, 0.01));

      expect(
        stripPhotoCellLetterboxColor('filmstrip'),
        const Color(0xFF0A0A0A),
      );
      expect(
        stripPhotoCellLetterboxColor('ai:dps'),
        const Color(0xFF121212),
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

  group('template overlay slots', () {
    test('places photos in catalog windows', () {
      const slots = [
        StripTemplateSlot(left: 0.1, top: 0.2, width: 0.8, height: 0.15),
        StripTemplateSlot(left: 0.1, top: 0.4, width: 0.8, height: 0.15),
        StripTemplateSlot(left: 0.1, top: 0.6, width: 0.8, height: 0.15),
      ];
      final cells = computeStripPhotoCellRects(
        frameId: 'f3:frame',
        stripWidth: stripW,
        stripHeight: stripH,
        shotCount: 3,
        templateSlots: slots,
      );
      expect(cells, hasLength(3));
      expect(cells.first.left, closeTo(60, 0.01));
      expect(cells.first.top, closeTo(360, 0.01));
      expect(cells.first.width, closeTo(480, 0.01));
      expect(cells.first.height, closeTo(270, 0.01));
    });

    test('resolveStripPreviewTemplateSlots uses catalog then defaults', () {
      expect(
        resolveStripPreviewTemplateSlots(
          frameId: 'classic',
          shotCount: 4,
          overlayUrl: 'https://example.com/x.png',
        ),
        isNull,
      );
      expect(
        resolveStripPreviewTemplateSlots(
          frameId: 'fr:x',
          shotCount: 4,
          overlayUrl: '',
        ),
        isNull,
      );
      final catalog = [
        const StripTemplateSlot(left: 0.1, top: 0.2, width: 0.8, height: 0.15),
        const StripTemplateSlot(left: 0.1, top: 0.4, width: 0.8, height: 0.15),
        const StripTemplateSlot(left: 0.1, top: 0.6, width: 0.8, height: 0.15),
        const StripTemplateSlot(left: 0.1, top: 0.8, width: 0.8, height: 0.15),
      ];
      expect(
        resolveStripPreviewTemplateSlots(
          frameId: 'fr:x',
          shotCount: 4,
          catalogSlots: catalog,
          overlayUrl: 'https://example.com/x.png',
        ),
        catalog,
      );
      final fallback = resolveStripPreviewTemplateSlots(
        frameId: 'f3:x',
        shotCount: 3,
        overlayUrl: 'https://example.com/x.png',
      );
      expect(fallback, hasLength(3));
    });
  });

  group('coverPhotoAlignmentForWindow', () {
    test('keeps heads in landscape wells and centers portrait wells', () {
      expect(
        coverPhotoAlignmentForWindow(1640, 900),
        Alignment.topCenter,
      );
      expect(
        coverPhotoAlignmentForWindow(800, 900),
        Alignment.center,
      );
    });
  });
}
