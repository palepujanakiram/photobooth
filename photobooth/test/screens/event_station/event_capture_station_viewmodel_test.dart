import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/event_station/event_capture_station_viewmodel.dart';
import 'package:photobooth/services/api_service.dart';
import 'package:photobooth/services/event_station_api.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/mock_api_dio.dart';

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
    expect(vm.statusFilter, 'PENDING');
    expect(vm.captures, isEmpty);
    expect(vm.stats.captures, 0);
    gate.complete();
    expect(await first, isTrue);
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
  }) async {
    throw StateError('boom');
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
