import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/kiosk_qr_payload.dart';

void main() {
  test('encode builds fotozen URI', () {
    final uri = KioskQrPayload.encode('ab12');
    expect(uri, contains('fotozen://kiosk'));
    expect(uri, contains('code=AB12'));
  });

  test('parse accepts custom URI', () {
    expect(
      KioskQrPayload.parse('fotozen://kiosk?code=xyz9'),
      'XYZ9',
    );
  });

  test('parse accepts plain alphanumeric code', () {
    expect(KioskQrPayload.parse('  booth_01 '), 'BOOTH_01');
  });

  test('parse returns null for garbage', () {
    expect(KioskQrPayload.parse('not a code!!!'), isNull);
  });

  test('encode can include event code', () {
    final uri = KioskQrPayload.encode('ab12', eventCode: 'wed');
    expect(uri, contains('code=AB12'));
    expect(uri, contains('event=WED'));
  });

  test('parseEventCode reads event query', () {
    expect(
      KioskQrPayload.parseEventCode('fotozen://kiosk?code=xyz9&event=gala'),
      'GALA',
    );
    expect(KioskQrPayload.parseEventCode('fotozen://kiosk?code=xyz9'), isNull);
  });
}
