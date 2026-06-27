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
}
