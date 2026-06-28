import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/customer_data_deletion.dart';
import 'package:photobooth/services/api_service.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:photobooth/utils/exceptions.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CustomerDataDeletion', () {
    test('calls server delete then clears local session', () async {
      SharedPreferences.setMockInitialValues({});
      final sm = SessionManager();
      sm.setSessionFromResponse({
        'id': 'sess-delete',
        'termsAccepted': true,
        'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'attemptsUsed': 0,
        'generatedImages': [],
        'expiresAt': DateTime.utc(2027, 1, 1).toIso8601String(),
      });

      final deleted = <String>[];
      final deletion = CustomerDataDeletion(
        sessionManager: sm,
        deleteSessionOnServer: (id) async {
          deleted.add(id);
        },
      );

      await deletion.deleteMyPhotos();

      expect(deleted, ['sess-delete']);
      expect(sm.hasSession, isFalse);
    });

    test('wipes local session when server id is already missing', () async {
      SharedPreferences.setMockInitialValues({});
      final sm = SessionManager();
      var serverCalled = false;

      final deletion = CustomerDataDeletion(
        sessionManager: sm,
        deleteSessionOnServer: (_) async {
          serverCalled = true;
        },
      );

      await deletion.deleteMyPhotos();

      expect(serverCalled, isFalse);
      expect(sm.hasSession, isFalse);
    });

    test('standard factory wires ApiService deleteSession', () async {
      SharedPreferences.setMockInitialValues({});
      final sm = SessionManager();
      sm.setSessionFromResponse({
        'id': 'sess-standard',
        'termsAccepted': true,
        'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'attemptsUsed': 0,
        'generatedImages': [],
        'expiresAt': DateTime.utc(2027, 1, 1).toIso8601String(),
      });

      final deleted = <String>[];
      final deletion = CustomerDataDeletion.standard(
        sessionManager: sm,
        apiService: _FakeDeleteApiService(deleted),
      );

      await deletion.deleteMyPhotos();

      expect(deleted, ['sess-standard']);
      expect(sm.hasSession, isFalse);
    });

    test('still wipes local session when server delete fails', () async {
      SharedPreferences.setMockInitialValues({});
      final sm = SessionManager();
      sm.setSessionFromResponse({
        'id': 'sess-fail',
        'termsAccepted': true,
        'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'attemptsUsed': 0,
        'generatedImages': [],
        'expiresAt': DateTime.utc(2027, 1, 1).toIso8601String(),
      });

      final deletion = CustomerDataDeletion(
        sessionManager: sm,
        deleteSessionOnServer: (_) async {
          throw ApiException('Server rejected delete');
        },
      );

      await expectLater(
        deletion.deleteMyPhotos(),
        throwsA(isA<ApiException>()),
      );
      expect(sm.hasSession, isFalse);
    });
  });

  group('deleteMyPhotosErrorMessage', () {
    test('uses ApiException user-facing message', () {
      expect(
        deleteMyPhotosErrorMessage(ApiException('Friendly')),
        'Friendly',
      );
    });

    test('falls back for unknown errors', () {
      expect(
        deleteMyPhotosErrorMessage(Exception('boom')),
        contains('Could not delete your photos'),
      );
    });
  });
}

class _FakeDeleteApiService extends ApiService {
  _FakeDeleteApiService(this.deleted);

  final List<String> deleted;

  @override
  Future<void> deleteSession(String sessionId) async {
    deleted.add(sessionId);
  }
}
