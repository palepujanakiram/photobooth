import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/event_station/event_capture_station_viewmodel.dart';
import 'package:photobooth/services/api_service.dart';
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
