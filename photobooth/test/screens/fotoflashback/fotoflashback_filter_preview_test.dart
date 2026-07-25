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
}
