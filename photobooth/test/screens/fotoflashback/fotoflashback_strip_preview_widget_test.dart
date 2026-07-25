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
    expect(find.byType(Image), findsNWidgets(4));
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
                id: 'd1',
                type: 'date',
                x: 0.5,
                y: 0.85,
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
}
