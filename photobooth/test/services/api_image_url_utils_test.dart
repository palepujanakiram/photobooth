import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/api_image_url_utils.dart';

void main() {
  test('resolveApiImageUrl absolutizes and strips whitespace', () {
    expect(
      resolveApiImageUrl('  /api/img/x.jpg  \n'),
      contains('/api/img/x.jpg'),
    );
    expect(
      resolveApiImageUrl('https://cdn.example/x.png'),
      'https://cdn.example/x.png',
    );
    expect(resolveApiImageUrl(''), '');
  });
}
