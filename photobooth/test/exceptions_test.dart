import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/exceptions.dart';

void main() {
  test('ApiException userFacingMessage hides JS 500 noise', () {
    final e = ApiException(
      "Cannot access 'foo' before initialization",
      500,
    );
    expect(
      e.userFacingMessage,
      'Something went wrong on the server. Please try again in a moment.',
    );
  });

  test('ApiException userFacingMessage passes through normal errors', () {
    final e = ApiException('Payment declined', 402);
    expect(e.userFacingMessage, 'Payment declined');
  });
}
