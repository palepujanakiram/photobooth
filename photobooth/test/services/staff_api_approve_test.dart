import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:photobooth/services/staff_api_service.dart';
import 'package:photobooth/services/staff_session_manager.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/utils/exceptions.dart';

class _FakeStaffSessionManager extends StaffSessionManager {
  @override
  Future<String?> getToken() async => 'staff-tok';

  @override
  Future<void> setSession({
    required String token,
    required String staffJson,
  }) async {}

  @override
  Future<void> clear() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Dio dio;
  late DioAdapter adapter;
  late StaffApiService api;
  Map<String, dynamic>? lastApproveBody;

  setUp(() {
    lastApproveBody = null;
    dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.kBaseUrl,
        validateStatus: (_) => true,
      ),
    );
    adapter = DioAdapter(dio: dio);
    dio.httpClientAdapter = adapter;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path.contains('/api/staff/payment/approve') &&
              options.data is Map) {
            lastApproveBody = Map<String, dynamic>.from(options.data as Map);
          }
          handler.next(options);
        },
      ),
    );
    api = StaffApiService(
      dio: dio,
      sessionManager: _FakeStaffSessionManager(),
    );
  });

  test('approvePayment requires paymentMode and posts body', () async {
    expect(
      () => api.approvePayment(paymentId: 'p1', paymentMode: '  '),
      throwsA(isA<ApiException>()),
    );
    adapter.onPost(
      '/api/staff/payment/approve',
      (s) => s.reply(200, {'ok': true}),
      data: Matchers.any,
    );
    await api.approvePayment(paymentId: 'pay-1', paymentMode: 'CASH');
    expect(lastApproveBody?['paymentId'], 'pay-1');
    expect(lastApproveBody?['paymentMode'], 'CASH');
  });
}
