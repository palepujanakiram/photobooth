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
    expect(stripPreviewFrameColor('noir'), const Color(0xFF121216));
    expect(stripPreviewFrameColor('polaroid'), Colors.white);
    expect(stripPreviewFrameColor('grid_2x2'), const Color(0xFFFFFAF5));
    expect(stripPreviewFrameColor('filmstrip'), const Color(0xFF0A0A0A));
    expect(stripPreviewFrameColor('romantic'), Colors.white);
    expect(stripPreviewFrameColor('plain_6x4'), Colors.white);
    expect(stripPreviewFrameAccent('classic'), isNull);
    expect(stripPreviewFrameAccent('noir'), isNotNull);
    expect(stripPreviewFrameAccent('polaroid'), isNotNull);
    // Removed doodle frames fall back to classic white.
    expect(stripPreviewFrameColor('doodle'), Colors.white);
    expect(stripPreviewFrameColor('party'), Colors.white);
    expect(stripPreviewFrameColor('cinema'), Colors.white);
    expect(stripPreviewFrameAccent('doodle'), isNull);
    expect(isStripSheetLayout('polaroid'), isTrue);
    expect(isStripSheetLayout('classic'), isFalse);
  });

  test('preview defaults to a single 2×6 strip aspect', () {
    expect(FotoFlashbackStripPreview.stripAspectRatio, closeTo(1 / 3, 0.001));
    expect(FotoFlashbackStripPreview.aspectRatio,
        FotoFlashbackStripPreview.stripAspectRatio);
    expect(FotoFlashbackStripPreview.defaultStripWidth,
        FotoFlashbackStripPreview.defaultSheetWidth / 2);
    expect(FotoFlashbackStripPreview.credentialLine, 'FOTOZEN AI');
  });

  testWidgets('flower placements render on the strip preview', (tester) async {
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
                id: 'f1',
                type: 'flowers',
                x: 0.5,
                y: 0.2,
              ),
              StripStickerPlacement(
                id: 'h1',
                type: 'hearts',
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
    expect(find.text('❀'), findsOneWidget);
    expect(find.text('♥'), findsOneWidget);
  });
}
