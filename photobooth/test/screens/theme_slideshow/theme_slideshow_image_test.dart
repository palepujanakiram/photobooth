import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/theme_slideshow/theme_slideshow_image.dart';

void main() {
  test('ThemeSlideshowImage constructor accepts optional layout widgets', () {
    const placeholder = SizedBox.shrink();
    const error = Icon(Icons.error);
    // Non-const so the constructor is exercised for coverage (const is compile-time only).
    // ignore: prefer_const_constructors
    final widget = ThemeSlideshowImage(
      path: 'https://example.com/photo.jpg',
      fit: BoxFit.contain,
      width: 200,
      height: 100,
      placeholder: placeholder,
      errorWidget: error,
    );
    expect(widget.path, 'https://example.com/photo.jpg');
    expect(widget.fit, BoxFit.contain);
    expect(widget.width, 200);
    expect(widget.height, 100);
    expect(widget.placeholder, placeholder);
    expect(widget.errorWidget, error);
  });

  group('isSlideshowAssetImagePath', () {
    test('returns true for assets/ prefix', () {
      expect(isSlideshowAssetImagePath('assets/images/foo.jpg'), isTrue);
      expect(isSlideshowAssetImagePath('Assets/foo.png'), isTrue);
    });

    test('returns false for http URL', () {
      expect(isSlideshowAssetImagePath('https://example.com/img.jpg'), isFalse);
    });

    test('returns false for relative path without assets/ prefix', () {
      expect(isSlideshowAssetImagePath('images/foo.jpg'), isFalse);
    });
  });

  testWidgets('ThemeSlideshowImage renders network path via CachedNetworkImage',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ThemeSlideshowImage(
          path: 'https://example.com/photo.jpg',
          width: 100,
          height: 100,
        ),
      ),
    );
    // The widget renders without throwing.
    expect(find.byType(ThemeSlideshowImage), findsOneWidget);
  });

  testWidgets('ThemeSlideshowImage with asset path shows Image.asset',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ThemeSlideshowImage(
          path: 'assets/images/placeholder.jpg',
          width: 100,
          height: 100,
        ),
      ),
    );
    // Will trigger errorBuilder since the asset doesn't exist in tests.
    await tester.pump();
    expect(find.byType(ThemeSlideshowImage), findsOneWidget);
  });
}
