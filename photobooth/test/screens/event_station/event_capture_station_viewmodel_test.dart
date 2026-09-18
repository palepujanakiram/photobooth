import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_station_models.dart';
import 'package:photobooth/screens/event_station/event_capture_station_viewmodel.dart';
import 'package:photobooth/services/api_service.dart';
import 'package:photobooth/services/event_station_api.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:photobooth/utils/app_strings.dart';
import 'package:photobooth/utils/event_bulk_import.dart';
import 'package:photobooth/utils/exceptions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/mock_api_dio.dart';
import '../../helpers/tiny_jpeg.dart';

class _SilentBoardApi extends EventStationApi {
  _SilentBoardApi() : super(dio: Dio(BaseOptions(validateStatus: (_) => true)));

  EventStationBoard board = const EventStationBoard();
  Object? listError;

  @override
  Future<EventStationBoard> fetchBoard() async {
    if (listError != null) throw listError!;
    return board;
  }
}

EventCaptureImportHooks _hooks(List<XFile> files) {
  return EventCaptureImportHooks(pickImages: () async => files);
}

XFile _jpegFile(String name) {
  return XFile.fromData(
    kTinyJpegBytes,
    name: name,
    mimeType: 'image/jpeg',
    path: '/tmp/$name',
    lastModified: DateTime(2024, 1, 1),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'kiosk_code': 'K1'});
    SessionManager().clearSession();
  });

  test('startNextGuest stores session', () async {
    final mock = createMockApiDio();
    final vm = EventCaptureStationViewModel(
      apiService: ApiService(dio: mock.dio),
    );
    expect(await vm.startNextGuest(), isTrue);
    expect(SessionManager().sessionId, 'sess-new');
    expect(vm.isBusy, isFalse);
  });

  test('startNextGuest maps API errors', () async {
    final mock = createMockApiDio();
    mock.dio.interceptors.insert(
      0,
      _FailAcceptTermsInterceptor(),
    );
    final vm = EventCaptureStationViewModel(
      apiService: ApiService(dio: mock.dio),
    );
    expect(await vm.startNextGuest(), isFalse);
    expect(vm.hasError, isTrue);
  });

  test('startNextGuest maps unexpected errors', () async {
    final vm = EventCaptureStationViewModel(apiService: _ThrowingApi());
    expect(await vm.startNextGuest(), isFalse);
    expect(vm.errorMessage, 'Could not start a new guest session.');
  });

  test('startNextGuest ignores overlapping taps', () async {
    final mock = createMockApiDio();
    final gate = Completer<void>();
    mock.dio.interceptors.insert(0, _HoldAcceptTermsInterceptor(gate));
    final vm = EventCaptureStationViewModel(
      apiService: ApiService(dio: mock.dio),
    );
    final first = vm.startNextGuest();
    await Future<void>.delayed(Duration.zero);
    expect(await vm.startNextGuest(), isFalse);
    gate.complete();
    expect(await first, isTrue);
    vm.dispose();
  });

  test('poll skips refresh while a guest start is in flight', () async {
    final mock = createMockApiDio();
    final gate = Completer<void>();
    mock.dio.interceptors.insert(0, _HoldAcceptTermsInterceptor(gate));
    final vm = EventCaptureStationViewModel(
      apiService: ApiService(dio: mock.dio),
      stationApi: EventStationApi(
        dio: mock.dio,
        readKioskCode: () async => 'K1',
        readEventCode: () async => 'GALA',
      ),
      pollInterval: const Duration(milliseconds: 5),
    );
    vm.startPolling();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final first = vm.startNextGuest();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(vm.isBusy, isTrue);
    expect(vm.statusFilter, 'ALL');
    expect(vm.captures, isEmpty);
    expect(vm.stats.captures, 0);
    gate.complete();
    expect(await first, isTrue);
    vm.dispose();
  });

  test('pickFromCard reports unavailable without import hooks', () async {
    final vm = EventCaptureStationViewModel();
    await vm.pickFromCard();
    expect(vm.errorMessage, AppStrings.eventStationImportUnavailable);
    vm.dispose();
  });

  test('pickFromCard ignores overlapping work and empty picker cancel', () async {
    final gate = Completer<List<XFile>>();
    final vm = EventCaptureStationViewModel(
      importHooks: EventCaptureImportHooks(pickImages: () => gate.future),
    );
    final first = vm.pickFromCard();
    await Future<void>.delayed(Duration.zero);
    await vm.pickFromCard();
    expect(vm.isBusy, isTrue);
    expect(await vm.importSelectedAsGuests(), 0);
    expect(await vm.startNextGuest(), isFalse);
    gate.complete(const []);
    await first;
    expect(vm.hasImportTray, isFalse);
    expect(vm.hasError, isFalse);
    vm.dispose();
  });

  test('pickFromCard stages photos, toggle, discard, and clear', () async {
    final vm = EventCaptureStationViewModel(
      stationApi: _SilentBoardApi(),
      importHooks: _hooks([_jpegFile('a.jpg'), _jpegFile('b.jpg')]),
    );
    await vm.pickFromCard();
    expect(vm.importItems, hasLength(2));
    expect(vm.hasImportTray, isTrue);
    expect(vm.importProgress, isNull);

    vm.discardSelectedImport();
    expect(vm.errorMessage, AppStrings.eventStationImportNoneSelected);

    vm.toggleImportSelection(vm.importItems.first.id);
    vm.discardSelectedImport();
    expect(vm.importItems, hasLength(1));
    expect(vm.hasError, isFalse);

    vm.clearImportTray();
    expect(vm.hasImportTray, isFalse);
    vm.dispose();
  });

  test('pickFromCard maps picker failures and unsupported files', () async {
    final failing = EventCaptureStationViewModel(
      importHooks: EventCaptureImportHooks(
        pickImages: () async => throw StateError('picker'),
      ),
    );
    await failing.pickFromCard();
    expect(failing.errorMessage, AppStrings.eventStationImportFailed);

    final apiFail = EventCaptureStationViewModel(
      importHooks: EventCaptureImportHooks(
        pickImages: () async => throw ApiException('no-card'),
      ),
    );
    await apiFail.pickFromCard();
    expect(apiFail.errorMessage, 'no-card');

    final empty = EventCaptureStationViewModel(
      importHooks: _hooks([
        XFile('no-such-event-import.heic'),
      ]),
    );
    await empty.pickFromCard();
    expect(empty.errorMessage, AppStrings.eventStationImportEmptyPick);
    failing.dispose();
    apiFail.dispose();
    empty.dispose();
  });

  test('importSelectedAsGuests creates a session per selected photo', () async {
    final mock = createMockApiDio();
    final board = _SilentBoardApi()
      ..board = const EventStationBoard(
        stats: EventStationStats(captures: 2),
      );
    final vm = EventCaptureStationViewModel(
      apiService: ApiService(dio: mock.dio),
      stationApi: board,
      importHooks: _hooks([_jpegFile('a.jpg'), _jpegFile('b.jpg')]),
    );
    await vm.pickFromCard();
    expect(await vm.importSelectedAsGuests(), 0);
    expect(vm.errorMessage, AppStrings.eventStationImportNoneSelected);

    vm.toggleImportSelection(vm.importItems.first.id);
    vm.toggleImportSelection(vm.importItems.last.id);
    expect(await vm.importSelectedAsGuests(), 2);
    expect(vm.hasImportTray, isFalse);
    expect(SessionManager().sessionId, 'sess-new');
    expect(vm.stats.captures, 2);
    vm.dispose();
  });

  test('importSelectedAsGuests keeps leftovers after a mid-batch failure', () async {
    final vm = EventCaptureStationViewModel(
      apiService: _PatchOnceApi(),
      stationApi: _SilentBoardApi(),
      importHooks: _hooks([_jpegFile('a.jpg'), _jpegFile('b.jpg')]),
    );
    await vm.pickFromCard();
    vm.toggleImportSelection(vm.importItems.first.id);
    vm.toggleImportSelection(vm.importItems.last.id);
    expect(await vm.importSelectedAsGuests(), 1);
    expect(vm.errorMessage, 'patch-fail');
    expect(vm.importItems, hasLength(1));
    vm.dispose();
  });

  test('importSelectedAsGuests maps session-id and unexpected failures', () async {
    final missing = EventCaptureStationViewModel(
      apiService: _NoIdApi(),
      stationApi: _SilentBoardApi(),
      importHooks: _hooks([_jpegFile('a.jpg')]),
    );
    await missing.pickFromCard();
    missing.toggleImportSelection(missing.importItems.first.id);
    expect(await missing.importSelectedAsGuests(), 0);
    expect(missing.errorMessage, AppStrings.eventStationImportMissingSession);

    final boom = EventCaptureStationViewModel(
      apiService: _ThrowingApi(),
      stationApi: _SilentBoardApi(),
      importHooks: _hooks([_jpegFile('a.jpg')]),
    );
    await boom.pickFromCard();
    boom.toggleImportSelection(boom.importItems.first.id);
    expect(await boom.importSelectedAsGuests(), 0);
    expect(boom.errorMessage, AppStrings.eventStationImportFailed);
    missing.dispose();
    boom.dispose();
  });

  test('refreshBoard can keep an existing import error', () async {
    final board = _SilentBoardApi();
    final vm = EventCaptureStationViewModel(
      apiService: _NoIdApi(),
      stationApi: board,
      importHooks: _hooks([_jpegFile('a.jpg')]),
    );
    await vm.pickFromCard();
    vm.toggleImportSelection(vm.importItems.first.id);
    await vm.importSelectedAsGuests();
    expect(vm.errorMessage, AppStrings.eventStationImportMissingSession);
    board.listError = StateError('poll');
    await vm.refreshBoard(clearErrorOnSuccess: false);
    expect(vm.errorMessage, AppStrings.eventStationImportMissingSession);
    vm.dispose();
  });
}

class _ThrowingApi extends ApiService {
  _ThrowingApi() : super(dio: Dio(BaseOptions(validateStatus: (_) => true)));

  @override
  Future<Map<String, dynamic>> acceptTermsAndCreateSession({
    String? kioskCode,
    String? source,
    String? selectedFrameId,
    bool includeSelectedFrameId = false,
    bool groupConsentAccepted = true,
    String? clientSessionId,
  }) async {
    throw StateError('boom');
  }
}

Map<String, dynamic> _sessionJson(String id) {
  return {
    'id': id,
    'termsAccepted': true,
    'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
    'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
    'attemptsUsed': 0,
    'generatedImages': <dynamic>[],
  };
}

class _NoIdApi extends ApiService {
  _NoIdApi() : super(dio: Dio(BaseOptions(validateStatus: (_) => true)));

  @override
  Future<Map<String, dynamic>> acceptTermsAndCreateSession({
    String? kioskCode,
    String? source,
    String? selectedFrameId,
    bool includeSelectedFrameId = false,
    bool groupConsentAccepted = true,
    String? clientSessionId,
  }) async {
    return {};
  }
}

class _PatchOnceApi extends ApiService {
  _PatchOnceApi() : super(dio: Dio(BaseOptions(validateStatus: (_) => true)));

  int _creates = 0;
  int _patches = 0;

  @override
  Future<Map<String, dynamic>> acceptTermsAndCreateSession({
    String? kioskCode,
    String? source,
    String? selectedFrameId,
    bool includeSelectedFrameId = false,
    bool groupConsentAccepted = true,
    String? clientSessionId,
  }) async {
    _creates += 1;
    return _sessionJson('sess-$_creates');
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
    _patches += 1;
    if (_patches > 1) throw ApiException('patch-fail');
    return _sessionJson(sessionId);
  }
}

class _HoldAcceptTermsInterceptor extends Interceptor {
  _HoldAcceptTermsInterceptor(this.gate);

  final Completer<void> gate;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('accept-terms')) {
      gate.future.then((_) => handler.next(options));
      return;
    }
    handler.next(options);
  }
}

class _FailAcceptTermsInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('accept-terms')) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: options,
            statusCode: 400,
            data: {'error': 'bad'},
          ),
        ),
      );
      return;
    }
    handler.next(options);
  }
}
