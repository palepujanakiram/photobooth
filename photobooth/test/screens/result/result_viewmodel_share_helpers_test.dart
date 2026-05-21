import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/result/kiosk_receipt_share_fallback.dart';
import 'package:photobooth/screens/result/result_viewmodel_share_helpers.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/utils/exceptions.dart';

void main() {
  test('applyKioskFallbackWhenReceiptShareEmpty no-op when receipt URL set', () {
    var receiptUrl = 'https://share/a';
    applyKioskFallbackWhenReceiptShareEmpty(
      KioskReceiptShareFallback(
        receiptShareUrl: receiptUrl,
        kioskFallbackShareUrl: 'https://kiosk/b',
        setReceiptShareUrl: (u) => receiptUrl = u,
        receiptShareLongUrl: null,
        kioskFallbackShareLongUrl: 'https://long/b',
        setReceiptShareLongUrl: (_) {},
        receiptShareExpiresAt: null,
        kioskFallbackShareExpiresAt: DateTime.utc(2026, 1, 1),
        setReceiptShareExpiresAt: (_) {},
      ),
    );
    expect(receiptUrl, 'https://share/a');
  });

  test('applyKioskFallbackWhenReceiptShareEmpty copies kiosk fields', () {
    var receiptUrl = '  ';
    String? longUrl;
    DateTime? expires;
    final kioskExpires = DateTime.utc(2026, 6, 1);

    applyKioskFallbackWhenReceiptShareEmpty(
      KioskReceiptShareFallback(
        receiptShareUrl: receiptUrl,
        kioskFallbackShareUrl: 'https://kiosk/fallback',
        setReceiptShareUrl: (u) => receiptUrl = u,
        receiptShareLongUrl: null,
        kioskFallbackShareLongUrl: 'https://long/fallback',
        setReceiptShareLongUrl: (u) => longUrl = u,
        receiptShareExpiresAt: null,
        kioskFallbackShareExpiresAt: kioskExpires,
        setReceiptShareExpiresAt: (t) => expires = t,
      ),
    );

    expect(receiptUrl, 'https://kiosk/fallback');
    expect(longUrl, 'https://long/fallback');
    expect(expires, kioskExpires);
  });

  test('applyKioskFallbackWhenReceiptShareEmpty skips empty kiosk URL', () {
    var receiptUrl = '';
    applyKioskFallbackWhenReceiptShareEmpty(
      KioskReceiptShareFallback(
        receiptShareUrl: receiptUrl,
        kioskFallbackShareUrl: '   ',
        setReceiptShareUrl: (u) => receiptUrl = u,
        receiptShareLongUrl: null,
        kioskFallbackShareLongUrl: null,
        setReceiptShareLongUrl: (_) {},
        receiptShareExpiresAt: null,
        kioskFallbackShareExpiresAt: null,
        setReceiptShareExpiresAt: (_) {},
      ),
    );
    expect(receiptUrl, '');
  });

  test('shareGeneratedImageUrlsOnWeb returns message when urls empty', () async {
    final message = await shareGeneratedImageUrlsOnWeb(
      urls: const [],
      shareText: (_, {subject, sharePositionOrigin}) async {},
    );
    expect(message, 'No images to share');
  });

  test('shareGeneratedImageUrlsOnWeb joins urls and shares', () async {
    String? sharedText;
    String? sharedSubject;
    final message = await shareGeneratedImageUrlsOnWeb(
      urls: const ['https://a.jpg', 'https://b.jpg'],
      shareText: (text, {sharePositionOrigin, String? subject}) async {
        sharedText = text;
        sharedSubject = subject;
      },
    );
    expect(message, isNull);
    expect(sharedText, 'https://a.jpg\nhttps://b.jpg');
    expect(sharedSubject, '${AppConstants.kBrandName} photos');
  });

  test('shareGeneratedImageUrlsOnWeb maps ShareException to user message', () async {
    final message = await shareGeneratedImageUrlsOnWeb(
      urls: const ['https://a.jpg'],
      shareText: (_, {subject, sharePositionOrigin}) async {
        throw ShareException('unsupported');
      },
    );
    expect(
      message,
      anyOf(
        'Sharing not supported in this browser. Link copied.',
        'Failed to share',
      ),
    );
  });

  test('shareGeneratedImageUrlsOnWeb maps unexpected errors', () async {
    final message = await shareGeneratedImageUrlsOnWeb(
      urls: const ['https://a.jpg'],
      shareText: (_, {subject, sharePositionOrigin}) async {
        throw Exception('network');
      },
    );
    expect(message, 'Failed to share: Exception: network');
  });
}
