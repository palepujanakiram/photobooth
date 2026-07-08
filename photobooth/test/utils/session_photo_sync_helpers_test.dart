import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_model.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:photobooth/utils/app_strings.dart';
import 'package:photobooth/utils/session_photo_sync_helpers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SessionManager().clearSession();
  });

  group('sessionResponseHasUserImage', () {
    test('false for null or empty session', () {
      expect(sessionResponseHasUserImage(null), isFalse);
      expect(sessionResponseHasUserImage({}), isFalse);
    });

    test('true when hasUserImage flag is set', () {
      expect(
        sessionResponseHasUserImage({'hasUserImage': true}),
        isTrue,
      );
    });

    test('true when preview or compressed url present', () {
      expect(
        sessionResponseHasUserImage({'userImageUrl': 'https://cdn/p.jpg'}),
        isTrue,
      );
      expect(
        sessionResponseHasUserImage({'compressedImageUrl': 'https://cdn/c.jpg'}),
        isTrue,
      );
    });

    test('false when urls are blank', () {
      expect(
        sessionResponseHasUserImage({
          'hasUserImage': false,
          'userImageUrl': '   ',
        }),
        isFalse,
      );
    });
  });

  group('ensureSessionPhotoOnServer', () {
    test('rejects empty session id', () async {
      final outcome = await ensureSessionPhotoOnServer(
        sessionId: '  ',
        photo: _testPhoto(),
      );
      expect(outcome.isReady, isFalse);
      expect(outcome.errorMessage, AppStrings.sessionPhotoSyncNoSession);
    });

    test('skips upload when server already has image', () async {
      var patchCalls = 0;
      final outcome = await ensureSessionPhotoOnServer(
        sessionId: 'sess-1',
        photo: _testPhoto(),
        fetchSessionFn: (_) async => {'hasUserImage': true},
        patchPhotoFn: ({required sessionId, required userImageUrl}) async {
          patchCalls += 1;
          return {};
        },
      );
      expect(outcome.isReady, isTrue);
      expect(outcome.alreadyPresent, isTrue);
      expect(patchCalls, 0);
    });

    test('uploads when image missing and verifies', () async {
      var fetchCount = 0;
      var patchCalls = 0;
      final outcome = await ensureSessionPhotoOnServer(
        sessionId: 'sess-2',
        photo: _testPhoto(),
        fetchSessionFn: (_) async {
          fetchCount += 1;
          return fetchCount == 1 ? {} : {'hasUserImage': true};
        },
        encodeForUploadFn: (_) async => 'data:image/jpeg;base64,abc',
        patchPhotoFn: ({required sessionId, required userImageUrl}) async {
          patchCalls += 1;
          expect(sessionId, 'sess-2');
          expect(userImageUrl, startsWith('data:image/jpeg'));
          return _sessionJson(sessionId);
        },
      );
      expect(outcome.isReady, isTrue);
      expect(outcome.uploaded, isTrue);
      expect(patchCalls, 1);
      expect(fetchCount, 2);
    });

    test('fails when verify still missing image', () async {
      final outcome = await ensureSessionPhotoOnServer(
        sessionId: 'sess-3',
        photo: _testPhoto(),
        fetchSessionFn: (_) async => {},
        encodeForUploadFn: (_) async => 'data:image/jpeg;base64,abc',
        patchPhotoFn: ({required sessionId, required userImageUrl}) async =>
            _sessionJson(sessionId),
      );
      expect(outcome.isReady, isFalse);
      expect(outcome.errorMessage, AppStrings.sessionPhotoSyncVerifyFailed);
    });
  });
}

PhotoModel _testPhoto() {
  return PhotoModel(
    id: 'p1',
    imageFile: XFile.fromData(
      Uint8List.fromList([0xFF, 0xD8, 0xFF]),
      name: 'test.jpg',
      mimeType: 'image/jpeg',
    ),
    capturedAt: DateTime.utc(2026, 1, 1),
  );
}

Map<String, dynamic> _sessionJson(String sessionId) {
  return {
    'id': sessionId,
    'termsAccepted': true,
    'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
    'attemptsUsed': 0,
    'generatedImages': <dynamic>[],
    'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
  };
}
