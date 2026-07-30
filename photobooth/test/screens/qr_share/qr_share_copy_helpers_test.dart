import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/qr_share/qr_share_copy_helpers.dart';
import 'package:photobooth/screens/result/result_viewmodel.dart';

void main() {
  group('QrShareUiSnapshot', () {
    test('equality compares share fields only', () {
      const a = QrShareUiSnapshot(
        qrData: 'https://share.example/s/1',
        longUrl: 'https://long.example',
        expiresAt: null,
        headline: 'Scan this QR on your phone to download a digital copy.',
        waLine: '',
      );
      const b = QrShareUiSnapshot(
        qrData: 'https://share.example/s/1',
        longUrl: 'https://long.example',
        expiresAt: null,
        headline: 'Scan this QR on your phone to download a digital copy.',
        waLine: '',
      );
      expect(a, equals(b));
    });

    test('fromViewModel uses parsed args when receipt empty', () {
      final vm = ResultViewModel(generatedImages: const []);
      final snap = QrShareUiSnapshot.fromViewModel(
        viewModel: vm,
        parsedShareUrl: 'https://route.example/s/0',
        parsedKioskShareUrl: null,
        parsedShareLongUrl: null,
        parsedShareExpiresAt: null,
        phone: '',
      );
      expect(snap.qrData, 'https://route.example/s/0');
    });
  });

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
