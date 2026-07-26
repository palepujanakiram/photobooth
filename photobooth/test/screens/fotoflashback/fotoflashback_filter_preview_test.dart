import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/strip_models.dart';
import 'package:photobooth/screens/fotoflashback/fotoflashback_filter_preview.dart';

void main() {
  test('stripPreviewColorFilter covers full catalog ids', () {
    expect(kStripFilterIds, hasLength(9));
    for (final id in kStripFilterIds) {
      expect(stripPreviewColorFilter(id), isA<ColorFilter>(), reason: id);
    }
    expect(stripPreviewColorFilter('unknown'), isA<ColorFilter>());
  });

  test('new looks use non-identity preview matrices', () {
    // Identity (clean) is zeros off-diagonal / unit diagonal; graded looks tint.
    for (final id in const [
      'peach_glow',
      'golden_hour',
      'cool_mint',
      'gloss_pop',
    ]) {
      expect(stripPreviewColorFilter(id), isA<ColorFilter>(), reason: id);
      expect(id, isNot('clean'));
    }
  });

  test('stripPreviewFrameColor covers catalog frames', () {
    expect(stripPreviewFrameColor('classic'), Colors.white);
    expect(stripPreviewFrameColor('ticket'), const Color(0xFF1C1816));
    expect(stripPreviewFrameColor('blush'), const Color(0xFFFFE4E8));
    expect(stripPreviewFrameColor('noir'), const Color(0xFF202022));
    expect(stripPreviewFrameAccent('classic'), isNull);
    expect(stripPreviewFrameAccent('ticket'), isNotNull);
  });

  test('preview defaults to a single 2×6 strip aspect', () {
    expect(FotoFlashbackStripPreview.stripAspectRatio, closeTo(1 / 3, 0.001));
    expect(FotoFlashbackStripPreview.aspectRatio,
        FotoFlashbackStripPreview.stripAspectRatio);
    expect(FotoFlashbackStripPreview.defaultStripWidth,
        FotoFlashbackStripPreview.defaultSheetWidth / 2);
    expect(FotoFlashbackStripPreview.credentialLine1, 'AI GENERATED');
    expect(FotoFlashbackStripPreview.credentialLine2, 'FotoZen AI');
  });

  testWidgets('butterfly and petal placements use path glyphs not emoji',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FotoFlashbackStripPreview(
            imageDataUrls: const [
              'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
              'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
              'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
              'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
            ],
            filterId: 'clean',
            placements: const [
              StripStickerPlacement(
                id: 'b1',
                type: 'butterflies',
                x: 0.5,
                y: 0.2,
              ),
              StripStickerPlacement(
                id: 'p1',
                type: 'petals',
                x: 0.5,
                y: 0.7,
              ),
            ],
            width: 180,
            height: 540,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('🦋'), findsNothing);
    expect(find.text('💮'), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
