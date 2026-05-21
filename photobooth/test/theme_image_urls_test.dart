import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/theme_image_urls.dart';

void main() {
  test('resolveThemeSampleImageUrl keeps absolute URLs', () {
    expect(
      resolveThemeSampleImageUrl('https://cdn.example.com/a.jpg'),
      'https://cdn.example.com/a.jpg',
    );
  });

  test('resolveThemeSampleImageUrl prefixes relative paths', () {
    final url = resolveThemeSampleImageUrl('/samples/hero.jpg');
    expect(url.endsWith('/samples/hero.jpg'), isTrue);
    expect(url.startsWith('http'), isTrue);
  });

  test('normalizeThemeImageUrl strips query', () {
    expect(
      normalizeThemeImageUrl('https://x.com/p?q=1'),
      'https://x.com/p',
    );
  });
}
