import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_preview_rotation.dart';

void main() {
  test('previewDisplayDimensions null previewSize odd turns returns (1, ratio)',
      () {
    final (w, h) = previewDisplayDimensions(
      previewSize: null,
      effectiveQuarterTurns: 1,
      displayAspectRatio: 0.75,
    );
    expect(w, 1.0);
    expect(h, 0.75);
  });

  test('previewDisplayDimensions null previewSize even turns returns (ratio, 1)',
      () {
    final (w, h) = previewDisplayDimensions(
      previewSize: null,
      effectiveQuarterTurns: 0,
      displayAspectRatio: 1.5,
    );
    expect(w, 1.5);
    expect(h, 1.0);
  });

  test('previewDisplayDimensions swaps width and height for odd quarter turns',
      () {
    const frame = Size(1280, 720);
    final (w, h) = previewDisplayDimensions(
      previewSize: frame,
      effectiveQuarterTurns: 1,
      displayAspectRatio: 720 / 1280,
    );
    expect(w, 720);
    expect(h, 1280);
  });

  test('previewDisplayDimensions keeps dimensions for even quarter turns', () {
    const frame = Size(1280, 720);
    final (w, h) = previewDisplayDimensions(
      previewSize: frame,
      effectiveQuarterTurns: 0,
      displayAspectRatio: 1280 / 720,
    );
    expect(w, 1280);
    expect(h, 720);
  });

  testWidgets('buildRotatedCoverPreview no rotation wraps in ClipRect',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: buildRotatedCoverPreview(
            preview: const ColoredBox(color: Colors.red),
            effectiveQuarterTurns: 0,
            baseAspectRatio: 16 / 9,
          ),
        ),
      ),
    );
    expect(find.byType(ClipRect), findsOneWidget);
    expect(find.byType(RotatedBox), findsNothing);
  });

  testWidgets('buildRotatedCoverPreview with rotation adds RotatedBox',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: buildRotatedCoverPreview(
            preview: const ColoredBox(color: Colors.blue),
            effectiveQuarterTurns: 1,
            baseAspectRatio: 16 / 9,
            frameSize: const Size(1280, 720),
          ),
        ),
      ),
    );
    expect(find.byType(RotatedBox), findsOneWidget);
    expect(find.byType(ClipRect), findsOneWidget);
  });
}
