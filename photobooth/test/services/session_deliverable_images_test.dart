import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/session_deliverable_images.dart';

void main() {
  test('isSessionProxyImageUrl accepts /api/img paths only', () {
    expect(isSessionProxyImageUrl('/api/img/generated/a.jpg'), isTrue);
    expect(
      isSessionProxyImageUrl('https://x.example/api/img/generated/a.jpg'),
      isTrue,
    );
    expect(isSessionProxyImageUrl('data:image/jpeg;base64,xx'), isFalse);
    expect(isSessionProxyImageUrl('https://cdn.example/a.jpg'), isFalse);
    expect(isSessionProxyImageUrl(null), isFalse);
  });

  test('mergeSessionProxyImageUrls dedupes and skips non-proxy', () {
    expect(
      mergeSessionProxyImageUrls(
        ['/api/img/generated/a.jpg', 'data:image/jpeg;base64,xx', 12],
        ['/api/img/generated/a.jpg', '/api/img/fotoflashback/b.jpg'],
      ),
      [
        '/api/img/generated/a.jpg',
        '/api/img/fotoflashback/b.jpg',
      ],
    );
  });
}
