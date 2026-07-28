import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/transformation_details/transformation_details_viewmodel.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:photobooth/services/staff_api_service.dart';
import 'package:photobooth/services/staff_session_manager.dart';
import 'package:photobooth/utils/exceptions.dart';

import '../fakes/fake_api_service.dart';

class _RunApi extends FakeApiService {
  _RunApi({this.payload, this.throwApi = false});

  final Map<String, dynamic>? payload;
  final bool throwApi;
  int fetchCount = 0;

  @override
  Future<Map<String, dynamic>> fetchGenerationRun(String runId) async {
    fetchCount++;
    if (throwApi) throw ApiException('run missing');
    return payload ?? {'id': runId};
  }
}

class _StaffSession extends StaffSessionManager {
  _StaffSession({this.token});

  final String? token;

  @override
  Future<String?> getToken() async => token;

  @override
  Future<void> setSession({
    required String token,
    required String staffJson,
  }) async {}

  @override
  Future<void> clear() async {}
}

class _StaffRunApi extends StaffApiService {
  _StaffRunApi({this.payload, this.throwApi = false});

  final Map<String, dynamic>? payload;
  final bool throwApi;
  int fetchCount = 0;

  @override
  Future<Map<String, dynamic>> fetchGenerationRun(String runId) async {
    fetchCount++;
    if (throwApi) throw ApiException('staff run missing');
    return payload ?? {'id': runId, 'status': 'staff-ok'};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('load populates payload via kiosk api when no staff token', () async {
    final api = _RunApi(payload: {'id': 'run-1', 'status': 'ok'});
    final vm = TransformationDetailsViewModel(
      runId: 'run-1',
      apiService: api,
      staffSessionManager: _StaffSession(token: null),
    );
    await vm.load();
    expect(vm.isLoading, isFalse);
    expect(vm.payload?['status'], 'ok');
    expect(api.fetchCount, 1);
  });

  test('load uses staff api when staff token is present', () async {
    final staff = _StaffRunApi(payload: {'id': 'run-1', 'status': 'staff-ok'});
    final kiosk = _RunApi(payload: {'id': 'run-1', 'status': 'kiosk-ok'});
    final vm = TransformationDetailsViewModel(
      runId: 'run-1',
      apiService: kiosk,
      staffApiService: staff,
      staffSessionManager: _StaffSession(token: 'staff-tok'),
    );
    await vm.load();
    expect(vm.payload?['status'], 'staff-ok');
    expect(staff.fetchCount, 1);
    expect(kiosk.fetchCount, 0);
  });

  test('load sets error on ApiException', () async {
    final vm = TransformationDetailsViewModel(
      runId: 'run-1',
      apiService: _RunApi(throwApi: true),
      staffSessionManager: _StaffSession(token: null),
    );
    await vm.load();
    expect(vm.errorMessage, isNotNull);
    expect(vm.payload, isNull);
  });

  test('activeSessionId reflects SessionManager', () {
    SessionManager().setSessionFromResponse({
      'id': 'sess-abc',
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.now().toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': [],
      'expiresAt': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
    });
    addTearDown(SessionManager().clearSession);

    final vm = TransformationDetailsViewModel(
      runId: 'run-1',
      apiService: _RunApi(),
      staffSessionManager: _StaffSession(token: null),
    );
    expect(vm.activeSessionId, 'sess-abc');
  });
}
