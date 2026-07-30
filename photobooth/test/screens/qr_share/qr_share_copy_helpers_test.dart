import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/qr_share/qr_share_copy_helpers.dart';

void main() {
  group('resolveQrShareData', () {
    test('prefers live receipt URL over route args', () {
      expect(
        resolveQrShareData(
          receiptShareUrl: 'https://live.example/s/1',
          kioskFallbackShareUrl: 'https://kiosk.example/s/2',
          parsedShareUrl: 'https://stale.example/s/0',
          parsedKioskShareUrl: 'https://stale-kiosk.example/s/9',
        ),
        'https://live.example/s/1',
      );
    });

    test('falls back to kiosk URL when receipt empty', () {
      expect(
        resolveQrShareData(
          receiptShareUrl: null,
          kioskFallbackShareUrl: 'https://kiosk.example/s/2',
          parsedShareUrl: null,
          parsedKioskShareUrl: 'https://stale-kiosk.example/s/9',
        ),
        'https://kiosk.example/s/2',
      );
    });

    test('uses parsed args when view model fields are still empty', () {
      expect(
        resolveQrShareData(
          receiptShareUrl: null,
          kioskFallbackShareUrl: null,
          parsedShareUrl: 'https://route.example/s/3',
          parsedKioskShareUrl: null,
        ),
        'https://route.example/s/3',
      );
    });
  });

  group('resolveQrShareLongUrl', () {
    test('prefers live long URL', () {
      expect(
        resolveQrShareLongUrl(
          receiptShareLongUrl: 'https://long.live',
          parsedShareLongUrl: 'https://long.stale',
        ),
        'https://long.live',
      );
    });
  });

  group('resolveQrShareExpiresAt', () {
    test('prefers live expiry', () {
      final live = DateTime.utc(2026, 7, 30, 12, 0);
      final stale = DateTime.utc(2026, 1, 1);
      expect(
        resolveQrShareExpiresAt(
          receiptShareExpiresAt: live,
          parsedShareExpiresAt: stale,
        ),
        live,
      );
    });
  });
}
