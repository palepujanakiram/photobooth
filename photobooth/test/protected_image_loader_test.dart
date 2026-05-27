import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/protected_image_loader.dart';

void main() {
  group('ProtectedImageLoader.isProtectedUrl', () {
    test('true for /api/img/generated paths', () {
      expect(
        ProtectedImageLoader.isProtectedUrl(
          'https://fotozenai.fly.dev/api/img/generated/abc.png?sessionId=s1',
        ),
        isTrue,
      );
      expect(
        ProtectedImageLoader.isProtectedUrl('/api/img/generated/abc.png'),
        isTrue,
      );
    });

    test('false for theme CDN URLs', () {
      expect(
        ProtectedImageLoader.isProtectedUrl(
          'https://cdn.example.com/themes/foo.jpg',
        ),
        isFalse,
      );
    });
  });
}
