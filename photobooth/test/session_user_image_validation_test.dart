import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/exceptions.dart';
import 'package:photobooth/utils/session_user_image_validation.dart';

void main() {
  test('accepts minimal valid jpeg data URL', () {
    const payload = 'aGVsbG8='; // "hello"
    const url = 'data:image/jpeg;base64,$payload';
    expect(
      () => SessionUserImageValidation.assertValidForSessionPatch(url),
      returnsNormally,
    );
  });

  test('rejects http URL', () {
    expect(
      () => SessionUserImageValidation.assertValidForSessionPatch(
        'https://example.com/x.jpg',
      ),
      throwsA(isA<ApiException>()),
    );
  });

  test('rejects empty string', () {
    expect(
      () => SessionUserImageValidation.assertValidForSessionPatch('  '),
      throwsA(isA<ApiException>()),
    );
  });
}
