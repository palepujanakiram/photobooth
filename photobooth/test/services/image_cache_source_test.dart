import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/image_cache_source.dart';

void main() {
  test('extractInlineImageDataUrl returns pure data URLs', () {
    const url = 'data:image/jpeg;base64,abc';
    expect(extractInlineImageDataUrl(url), url);
    expect(isInlineImageCacheUrl(url), isTrue);
  });

  test('extractInlineImageDataUrl extracts embedded data URLs', () {
    const embedded = 'data:image/jpeg;base64,abc';
    const url = 'https://example.com/$embedded';
    expect(extractInlineImageDataUrl(url), embedded);
    expect(isInlineImageCacheUrl(url), isTrue);
  });

  test('extractInlineImageDataUrl returns null for normal http URLs', () {
    expect(
      extractInlineImageDataUrl('https://example.com/images/a.jpg'),
      isNull,
    );
    expect(isInlineImageCacheUrl('https://example.com/images/a.jpg'), isFalse);
  });

  test('decodeInlineImageDataUrl decodes base64 payload', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final dataUrl =
        'data:image/jpeg;base64,${base64Encode(bytes)}';
    expect(decodeInlineImageDataUrl(dataUrl), bytes);
  });

  test('decodeInlineImageDataUrl returns null for invalid payload', () {
    expect(decodeInlineImageDataUrl('data:image/jpeg;base64,@@@'), isNull);
    expect(decodeInlineImageDataUrl('data:image/jpeg;base64'), isNull);
  });

  test('catalog cache keys prefer theme/frame id over URL hash', () {
    expect(catalogCacheKeyForTheme(''), isNull);
    expect(catalogCacheKeyForTheme('  '), isNull);
    expect(catalogCacheKeyForTheme('bad id'), isNull);
    expect(catalogCacheKeyForTheme('Hero-01'), 'theme-hero-01');
    expect(catalogCacheKeyForFrame('frame_9'), 'frame-frame_9');
    expect(catalogCacheKeyForFrame(null), isNull);
    expect(
      catalogImageCacheFileStem(
        cacheKey: catalogCacheKeyForTheme('t1'),
        imageUrl: 'https://a.example/old.png?v=1',
      ),
      'theme-t1',
    );
    expect(
      catalogImageCacheFileStem(
        cacheKey: catalogCacheKeyForTheme('t1'),
        imageUrl: 'https://b.example/new.webp?v=2',
      ),
      'theme-t1',
    );
    final a = catalogImageCacheFileStem(
      imageUrl: 'https://fly.dev/x.png?token=a',
    );
    final b = catalogImageCacheFileStem(
      imageUrl: 'https://fly.dev/x.png?token=b',
    );
    expect(a, b);
    expect(a, isNot(catalogImageCacheFileStem(imageUrl: 'https://fly.dev/y.png')));
  });

  test('url hash stem and extension cover edge cases', () {
    expect(imageCacheFileExtension('https://x/a.PNG'), '.png');
    expect(imageCacheFileExtension('https://x/a'), '.jpg');
    expect(imageCacheFileExtension('https://x/a.toolongext'), '.jpg');
    expect(imageCacheFileExtension('https://x/dir.with.dot/file'), '.jpg');
    expect(imageCacheFileExtension('plain.jpg'), '.jpg');
    expect(urlHashImageCacheStem('not a url'), isNotEmpty);
    final longId = 'a' * 90;
    expect(sanitizeCatalogCacheToken(longId)?.length, 80);
    expect(
      catalogImageCacheFileStem(cacheKey: 'not valid!', imageUrl: 'https://x/a.jpg'),
      urlHashImageCacheStem('https://x/a.jpg'),
    );
    final longUrl = 'https://example.com/${'z' * 200}.jpg';
    expect(urlHashImageCacheStem(longUrl).length, lessThan(200));
  });
}
