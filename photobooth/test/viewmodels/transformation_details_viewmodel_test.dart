import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/transformation_details/transformation_details_viewmodel.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:photobooth/utils/exceptions.dart';

import '../fakes/fake_api_service.dart';

class _RunApi extends FakeApiService {
  _RunApi({this.payload, this.throwApi = false});

  final Map<String, dynamic>? payload;
  final bool throwApi;

  @override
  Future<Map<String, dynamic>> fetchGenerationRun(String runId) async {
    if (throwApi) throw ApiException('run missing');
    return payload ?? {'id': runId};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('load populates payload', () async {
    final vm = TransformationDetailsViewModel(
      runId: 'run-1',
      apiService: _RunApi(payload: {'id': 'run-1', 'status': 'ok'}),
    );
    await vm.load();
    expect(vm.isLoading, isFalse);
    expect(vm.payload?['status'], 'ok');
  });

  test('load sets error on ApiException', () async {
    final vm = TransformationDetailsViewModel(
      runId: 'run-1',
      apiService: _RunApi(throwApi: true),
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
    );
    expect(vm.activeSessionId, 'sess-abc');
  });
}
