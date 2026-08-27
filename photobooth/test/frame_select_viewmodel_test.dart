import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/kiosk_frame_model.dart';
import 'package:photobooth/screens/frame_select/frame_select_viewmodel.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fakes/fake_api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('loadFrames populates frames on success', () async {
    final api = FakeApiService(
      kioskFrames: [
        const KioskFrameModel(
          id: 'f1',
          name: 'Frame',
          overlayUrl: 'https://cdn.example/overlay.png',
        ),
      ],
    );
    final vm = FrameSelectViewModel(apiService: api);
    final ok = await vm.loadFrames();
    expect(ok, isTrue);
    expect(vm.frames, hasLength(1));
    expect(api.getKioskFramesCalls, 1);
    expect(vm.isLoading, isFalse);
  });

  test('loadFrames sets error on ApiException', () async {
    final api = FakeApiService(framesThrow: true);
    final vm = FrameSelectViewModel(apiService: api);
    final ok = await vm.loadFrames();
    expect(ok, isFalse);
    expect(vm.errorMessage, isNotNull);
    expect(vm.frames, isEmpty);
  });

  test('patchSelectedFrame fails without session', () async {
    SessionManager().clearSession();
    final vm = FrameSelectViewModel(apiService: FakeApiService());
    final ok = await vm.patchSelectedFrameAndSyncSession(
      includeSelectedFrameId: true,
      selectedFrameId: 'f1',
    );
    expect(ok, isFalse);
    expect(vm.errorMessage, contains('session'));
  });

  test('offline frame selection is persisted locally', () async {
    SessionManager().setSessionFromResponse({
      'id': 'offline-frame',
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': <dynamic>[],
      'expiresAt': DateTime.utc(2026, 12, 31).toIso8601String(),
      'offline': true,
      'eventId': 'event-1',
    });
    final api = FakeApiService(patchThrows: true);
    final vm = FrameSelectViewModel(apiService: api);
    expect(
      await vm.patchSelectedFrameAndSyncSession(
        includeSelectedFrameId: true,
        selectedFrameId: 'frame-1',
      ),
      isTrue,
    );
    expect(SessionManager().currentSession?.selectedFrameId, 'frame-1');
    expect(SessionManager().currentSession?.eventId, 'event-1');
  });
}
