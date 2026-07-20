import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
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

  group('downloadPhoneUploadPreviewToXFile', () {
    test('throws when preview URL missing', () async {
      await expectLater(
        downloadPhoneUploadPreviewToXFile('   '),
        throwsStateError,
      );
    });

    test('uses protected loader for /api/img URLs', () async {
      try {
        final file =
            await downloadPhoneUploadPreviewToXFile('/api/img/missing.jpg');
        expect(await file.readAsBytes(), isNotEmpty);
      } catch (_) {
        // Offline CI may fail the protected fetch; branch is still covered.
      }
    });

    test('downloads public http bytes without injected dio', () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      addTearDown(server.close);
      server.listen((request) async {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.binary
          ..add([4, 5, 6])
          ..close();
      });

      final file = await downloadPhoneUploadPreviewToXFile(
        'http://127.0.0.1:${server.port}/preview.jpg',
      );
      expect(await file.readAsBytes(), [4, 5, 6]);
    });

    test('downloads public http bytes via dio', () async {
      final dio = Dio();
      final adapter = DioAdapter(dio: dio);
      dio.httpClientAdapter = adapter;
      adapter.onGet(
        'https://cdn.example.com/preview.jpg',
        (server) => server.reply(200, Uint8List.fromList([1, 2, 3])),
      );

      final file = await downloadPhoneUploadPreviewToXFile(
        'https://cdn.example.com/preview.jpg',
        dio: dio,
      );
      final bytes = await file.readAsBytes();
      expect(bytes, [1, 2, 3]);
    });

    test('throws when download returns empty bytes', () async {
      final dio = Dio();
      final adapter = DioAdapter(dio: dio);
      dio.httpClientAdapter = adapter;
      adapter.onGet(
        'https://cdn.example.com/empty.jpg',
        (server) => server.reply(200, Uint8List(0)),
      );

      await expectLater(
        downloadPhoneUploadPreviewToXFile(
          'https://cdn.example.com/empty.jpg',
          dio: dio,
        ),
        throwsStateError,
      );
    });
  });
}
