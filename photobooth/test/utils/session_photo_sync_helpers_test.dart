import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_model.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:photobooth/utils/app_strings.dart';
import 'package:photobooth/utils/exceptions.dart';
import 'package:photobooth/utils/session_photo_sync_helpers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../fakes/fake_api_service.dart';

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

    test('true when hasCompressedImage flag is set', () {
      expect(
        sessionResponseHasUserImage({'hasCompressedImage': true}),
        isTrue,
      );
    });

    test('false when only lightweight preview url is present', () {
      expect(
        sessionResponseHasUserImage({
          'hasUserImage': false,
          'userImageUrl': 'https://cdn/preview.jpg',
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

    test('uses default api service fetchSession when callbacks omitted', () async {
      final api = FakeApiService(fetchSessionResult: {'hasUserImage': true});
      final outcome = await ensureSessionPhotoOnServer(
        sessionId: 'sess-api-default',
        photo: _testPhoto(),
        apiService: api,
      );
      expect(outcome.alreadyPresent, isTrue);
      expect(api.fetchSessionCalls, greaterThan(0));
    });

    test('uploads through default api patch helper', () async {
      forceWebMaterializeForSessionPhotoSyncTest = true;
      addTearDown(() => forceWebMaterializeForSessionPhotoSyncTest = false);

      var fetchCount = 0;
      final api = FakeApiService();
      final outcome = await ensureSessionPhotoOnServer(
        sessionId: 'sess-default-patch',
        photo: _testPhoto(),
        apiService: _FetchThenReadyApi(api, () => fetchCount++),
        encodeForUploadFn: (_) async => 'data:image/jpeg;base64,abc',
      );
      expect(outcome.uploaded, isTrue);
      expect(fetchCount, greaterThan(0));
    });

    test('maps ApiException to error message', () async {
      final outcome = await ensureSessionPhotoOnServer(
        sessionId: 'sess-api',
        photo: _testPhoto(),
        fetchSessionFn: (_) async => {},
        encodeForUploadFn: (_) async => 'data:image/jpeg;base64,abc',
        patchPhotoFn: ({required sessionId, required userImageUrl}) async {
          throw ApiException('patch denied');
        },
      );
      expect(outcome.errorMessage, 'patch denied');
    });

    test('maps generic failures to sync failed message', () async {
      final outcome = await ensureSessionPhotoOnServer(
        sessionId: 'sess-generic',
        photo: _testPhoto(),
        fetchSessionFn: (_) async => throw StateError('boom'),
      );
      expect(outcome.errorMessage, contains(AppStrings.sessionPhotoSyncFailed));
    });
  });

  group('materializeWebXFileForSessionSync', () {
    test('rejects empty web bytes', () async {
      await expectLater(
        materializeWebXFileForSessionSync(
          XFile.fromData(Uint8List(0), name: 'empty.jpg'),
        ),
        throwsA(isA<ApiException>()),
      );
    });

    test('returns jpeg xfile for non-empty bytes', () async {
      final file = await materializeWebXFileForSessionSync(
        XFile.fromData(
          Uint8List.fromList([0xFF, 0xD8, 0xFF]),
          name: 'web.jpg',
          mimeType: 'image/jpeg',
        ),
      );
      expect(await file.readAsBytes(), isNotEmpty);
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

class _FetchThenReadyApi extends FakeApiService {
  _FetchThenReadyApi(this._inner, this._onFetch);

  final FakeApiService _inner;
  final void Function() _onFetch;
  var _fetchCount = 0;

  @override
  Future<Map<String, dynamic>?> fetchSession(String sessionId) async {
    _onFetch();
    _fetchCount++;
    if (_fetchCount == 1) return {};
    return {'hasUserImage': true};
  }

  @override
  Future<Map<String, dynamic>> updateSession({
    required String sessionId,
    String? userImageUrl,
    String? selectedThemeId,
    bool includeSelectedFrameId = false,
    String? selectedFrameId,
    int? personCount,
    Map<String, dynamic>? framingMetadata,
  }) async {
    return _sessionJson(sessionId);
  }
}
