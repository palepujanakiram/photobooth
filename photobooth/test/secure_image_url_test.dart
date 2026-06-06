import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/secure_image_url.dart';

void main() {
  test('absolutize prefixes relative api img path', () {
    final url = SecureImageUrl.absolutize('/api/img/abc');
    expect(url, startsWith('http'));
    expect(url, contains('/api/img/abc'));
  });

  test('previewUrlFromStepMap reads previewImageUrl', () {
    final url = SecureImageUrl.previewUrlFromStepMap({
      'previewImageUrl': '/api/img/preview',
    });
    expect(url, isNotNull);
    expect(url!, contains('/api/img/preview'));
  });

  test('previewUrlFromStepMap returns null when missing', () {
    expect(SecureImageUrl.previewUrlFromStepMap({}), isNull);
  });
}
