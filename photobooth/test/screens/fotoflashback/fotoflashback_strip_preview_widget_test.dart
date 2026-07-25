import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/strip_models.dart';
import 'package:photobooth/screens/fotoflashback/fotoflashback_filter_preview.dart';

void main() {
  // Minimal 1x1 JPEG
  const jpegB64 =
      '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkS'
      'Ew8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwL'
      'DBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIy'
      'MjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAn/'
      'xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEA'
      'AAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAGfAP/EABQQAQAAAAAAAAAAAAAAAAAA'
      'AAD/2gAIAQEAAQUCf//EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQMBAT8Bf//EABQR'
      'AQAAAAAAAAAAAAAAAAAAAAD/2gAIAQIBAT8Bf//Z';

  testWidgets('FotoFlashbackStripPreview renders a single 4-shot strip', (
    tester,
  ) async {
    final url = 'data:image/jpeg;base64,$jpegB64';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FotoFlashbackStripPreview(
            imageDataUrls: List.filled(4, url),
            filterId: 'mono',
          ),
        ),
      ),
    );
    // Each cell uses cover (blur fill) + contain (full frame) → 8 Images.
    expect(find.byType(Image), findsNWidgets(8));
    expect(base64Decode(jpegB64), isNotEmpty);
  });

  testWidgets('FotoFlashbackStripPreview accepts raw base64 and placeholders', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FotoFlashbackStripPreview(
            imageDataUrls: [jpegB64],
            filterId: 'clean',
          ),
        ),
      ),
    );
    expect(find.byType(ColoredBox), findsWidgets);
  });

  testWidgets('FotoFlashbackStripPreview renders draggable placements', (
    tester,
  ) async {
    final url = 'data:image/jpeg;base64,$jpegB64';
    String? movedId;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FotoFlashbackStripPreview(
            imageDataUrls: List.filled(4, url),
            filterId: 'clean',
            placements: const [
              StripStickerPlacement(
                id: 'h1',
                type: 'hearts',
                x: 0.5,
                y: 0.3,
              ),
              StripStickerPlacement(
                id: 'c1',
                type: 'confetti',
                x: 0.5,
                y: 0.7,
              ),
            ],
            onMovePlacement: (id, x, y) => movedId = id,
          ),
        ),
      ),
    );
    expect(find.text('♥'), findsOneWidget);
    await tester.drag(find.text('♥'), const Offset(12, 8));
    expect(movedId, 'h1');
  });

  testWidgets('placements keep distinct Positioned tops per photo cell', (
    tester,
  ) async {
    final url = 'data:image/jpeg;base64,$jpegB64';
    const placements = [
      StripStickerPlacement(id: 'a', type: 'hearts', x: 0.8, y: 0.125),
      StripStickerPlacement(id: 'b', type: 'hearts', x: 0.2, y: 0.375),
      StripStickerPlacement(id: 'c', type: 'hearts', x: 0.8, y: 0.625),
      StripStickerPlacement(id: 'd', type: 'hearts', x: 0.2, y: 0.875),
    ];
    const h = 400.0;
    const w = h * FotoFlashbackStripPreview.aspectRatio;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FotoFlashbackStripPreview(
            imageDataUrls: List.filled(4, url),
            filterId: 'clean',
            placements: placements,
            width: w,
            height: h,
          ),
        ),
      ),
    );
    expect(find.text('♥'), findsNWidgets(4));
    final tops = tester
        .widgetList<Positioned>(find.byType(Positioned))
        .map((p) => p.top)
        .whereType<double>()
        .toList();
    // Four sticker Positioned widgets should not share one top (the Stack bug).
    expect(tops.toSet().length, greaterThanOrEqualTo(4));
  });
}
