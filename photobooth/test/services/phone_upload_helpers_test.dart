import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/phone_upload_helpers.dart';

void main() {
  group('PhoneUploadLinkInfo.tryParse', () {
    test('parses token url and expiresAt', () {
      final info = PhoneUploadLinkInfo.tryParse({
        'token': 'abc123',
        'url': 'https://fotozen.ai/u/abc123',
        'expiresAt': '2026-07-14T12:00:00.000Z',
      });
      expect(info, isNotNull);
      expect(info!.token, 'abc123');
      expect(info.url, 'https://fotozen.ai/u/abc123');
      expect(info.expiresAt, isNotNull);
    });

    test('returns null when token or url missing', () {
      expect(PhoneUploadLinkInfo.tryParse({'token': 'x'}), isNull);
      expect(PhoneUploadLinkInfo.tryParse({'url': 'https://x'}), isNull);
      expect(PhoneUploadLinkInfo.tryParse(null), isNull);
    });
  });

  group('phoneUploadSessionReady', () {
    test('true when hasUserImage flag set', () {
      expect(phoneUploadSessionReady({'hasUserImage': true}), isTrue);
      expect(phoneUploadSessionReady({'hasCompressedImage': true}), isTrue);
      expect(phoneUploadSessionReady({'hasUserImage': false}), isFalse);
      expect(phoneUploadSessionReady(null), isFalse);
    });
  });

  group('phoneUploadPreviewUrlFromSession', () {
    test('prefers userImageUrl then preview field', () {
      expect(
        phoneUploadPreviewUrlFromSession({
          'userImageUrl': 'https://cdn/preview.jpg',
        }),
        'https://cdn/preview.jpg',
      );
      expect(
        phoneUploadPreviewUrlFromSession({
          'userImagePreviewUrl': 'https://cdn/thumb.jpg',
        }),
        'https://cdn/thumb.jpg',
      );
      expect(phoneUploadPreviewUrlFromSession({}), isNull);
    });
  });
}
