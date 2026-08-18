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

  test('withSessionId appends session for absolute api img URLs', () {
    final url = SecureImageUrl.withSessionId(
      'https://fotozenai.fly.dev/api/img/generated/abc.jpg',
      sessionId: 'sess-1',
      kioskToken: 'kiosk-1',
    );
    expect(url, contains('/api/img/generated/abc.jpg'));
    expect(url, contains('sessionId=sess-1'));
    expect(url, contains('kioskToken=kiosk-1'));
  });

  test('withSessionId stamps event station codes and skips operator token', () {
    final url = SecureImageUrl.withSessionId(
      '/api/img/generated/abc.jpg',
      sessionId: 'guest-1',
      kioskToken: 'op-token',
      kioskCode: 'K1',
      eventCode: 'GALA',
    );
    expect(url, contains('sessionId=guest-1'));
    expect(url, contains('kioskCode=K1'));
    expect(url, contains('eventCode=GALA'));
    expect(url, isNot(contains('kioskToken=')));
  });

  test('previewUrlFromStepMap returns null when missing', () {
    expect(SecureImageUrl.previewUrlFromStepMap({}), isNull);
  });
}
