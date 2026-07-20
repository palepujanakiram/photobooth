import 'dart:async';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/models/payment_initiate_result.dart';
import 'package:photobooth/screens/photo_capture/photo_model.dart';
import 'package:photobooth/screens/pre_payment/pre_payment_viewmodel.dart';
import 'package:photobooth/services/app_settings_manager.dart';
import 'package:photobooth/services/payment_push_coordinator.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:photobooth/utils/app_strings.dart';
import 'package:photobooth/utils/constants.dart';
import '../../fakes/fake_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SessionManager().clearSession();
  });

  group('PrePaymentViewModel', () {
    test('loadPaymentQr fails without session', () async {
      final vm = PrePaymentViewModel(
        appSettingsManager: AppSettingsManager(
          apiService: FakeApiService(),
          resolveKioskCode: () async => null,
        ),
        apiService: FakeApiService(),
      );
      await vm.loadPaymentQr();
      expect(vm.paymentInitError, contains('No session'));
      expect(vm.paymentInitInProgress, isFalse);
    });

    test('loadPaymentQr initiates payment and starts polling', () async {
      fakeAsync((async) {
        SessionManager().setSessionFromResponse(_sessionJson('sess-pay'));
        final api = FakeApiService();
        final settings = AppSettingsManager(
          apiService: api,
          resolveKioskCode: () async => null,
        );
        // Seed settings through a lightweight subclass workaround:
        final vm = PrePaymentViewModel(
          appSettingsManager: _SeededAppSettingsManager(
            settings: AppSettingsModel(
              parallelImageCount: 1,
              initialPrice: 150,
            ),
          ),
          apiService: api,
          sessionManager: SessionManager(),
        );

        vm.loadPaymentQr();
        async.elapse(Duration.zero);
        async.flushMicrotasks();

        expect(vm.hasPaymentQrPayload, isTrue);
        expect(vm.paymentInitInProgress, isFalse);
        expect(api.initiatePaymentCalls, 1);

        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();
      });
    });

    test('retryLoadPaymentQr forces a fresh initiate', () async {
      SessionManager().setSessionFromResponse(_sessionJson('sess-retry'));
      final api = FakeApiService();
      final vm = PrePaymentViewModel(
        appSettingsManager: _SeededAppSettingsManager(),
        apiService: api,
        sessionManager: SessionManager(),
      );

      await vm.loadPaymentQr();
      await vm.retryLoadPaymentQr();

      expect(api.initiatePaymentCalls, greaterThanOrEqualTo(2));
    });

    test('loadPaymentQr retries once when QR payload missing', () async {
      fakeAsync((async) {
        SessionManager().setSessionFromResponse(_sessionJson('sess-miss'));
        final api = FakeApiService(
          initiatePaymentResult: PaymentInitiateResult(
            id: 'pay-empty',
            status: 'PENDING',
          ),
        );
        final vm = PrePaymentViewModel(
          appSettingsManager: _SeededAppSettingsManager(),
          apiService: api,
          sessionManager: SessionManager(),
        );

        vm.loadPaymentQr();
        async.elapse(Duration.zero);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 900));
        async.flushMicrotasks();

        expect(api.initiatePaymentCalls, 2);
        expect(vm.paymentInitError, isNotNull);
      });
    });

    test('loadPaymentQr maps ApiException to paymentInitError', () async {
      SessionManager().setSessionFromResponse(_sessionJson('sess-api'));
      final vm = PrePaymentViewModel(
        appSettingsManager: _SeededAppSettingsManager(),
        apiService: FakeApiService(initiatePaymentThrows: true),
        sessionManager: SessionManager(),
      );

      await vm.loadPaymentQr();
      expect(vm.paymentInitError, 'initiate failed');
    });

    test('loadPaymentQr reports generic failures', () async {
      SessionManager().setSessionFromResponse(_sessionJson('sess-boom'));
      final vm = PrePaymentViewModel(
        appSettingsManager: _SeededAppSettingsManager(),
        apiService: _ThrowingInitiateApi(),
        sessionManager: SessionManager(),
      );

      await vm.loadPaymentQr();
      expect(vm.paymentInitError, contains('Payment setup failed'));
    });

    test('onFcmPaymentPush approved invokes callback once', () async {
      final vm = PrePaymentViewModel(
        appSettingsManager: _SeededAppSettingsManager(),
        apiService: FakeApiService(),
      );
      var approved = 0;
      vm.onApproved = () => approved++;

      await vm.onFcmPaymentPush(
        PaymentPushPayload(
          type: PaymentPushCoordinator.typeApproved,
          paymentId: 'p1',
          body: 'Paid',
        ),
      );
      await vm.onFcmPaymentPush(
        PaymentPushPayload(
          type: PaymentPushCoordinator.typeApproved,
          paymentId: 'p1',
        ),
      );

      expect(approved, 1);
      expect(vm.fcmPaymentPushSuccess, isTrue);
    });

    test('onFcmPaymentPush failed sets detail', () async {
      final vm = PrePaymentViewModel(
        appSettingsManager: _SeededAppSettingsManager(),
        apiService: FakeApiService(),
      );

      await vm.onFcmPaymentPush(
        PaymentPushPayload(
          type: PaymentPushCoordinator.typeFailed,
          paymentId: 'p1',
        ),
      );

      expect(vm.fcmPaymentPushSuccess, isFalse);
      expect(vm.fcmPaymentStatusDetail, AppStrings.paymentFailedRetryBody);
    });

    test('payment poll approves via fetchPaymentStatus', () async {
      await _withPollingVm(
        fetchPaymentStatusResult: {'status': 'APPROVED'},
        afterLoad: (vm, async) {
          async.elapse(const Duration(seconds: 3));
          async.flushMicrotasks();
          expect(vm.fcmPaymentPushSuccess, isTrue);
        },
      );
    });

    test('session poll approves via fetchSession', () async {
      await _withPollingVm(
        fetchPaymentStatusResult: const {'status': 'PENDING'},
        fetchSessionResult: {'paymentStatus': 'APPROVED'},
        afterLoad: (vm, async) {
          async.elapse(const Duration(seconds: 3));
          async.flushMicrotasks();
          expect(vm.fcmPaymentPushSuccess, isTrue);
        },
      );
    });

    test('isDeadPollingFallbackVisible when both polls fail repeatedly', () {
      final vm = PrePaymentViewModel(
        appSettingsManager: _SeededAppSettingsManager(),
        apiService: FakeApiService(),
      );
      vm.setPollingFailureStreaksForTest(
        paymentFailures: 10,
        sessionFailures: 10,
      );
      expect(vm.isDeadPollingFallbackVisible, isTrue);
    });

    test('refreshPaymentPolling clears failure streaks and restarts', () async {
      SessionManager().setSessionFromResponse(_sessionJson('sess-refresh'));
      final api = FakeApiService(
        fetchSessionResult: {'paymentStatus': 'PENDING'},
      );
      final vm = PrePaymentViewModel(
        appSettingsManager: _SeededAppSettingsManager(),
        apiService: api,
        sessionManager: SessionManager(),
      );

      await vm.loadPaymentQr();
      await vm.refreshPaymentPolling();
      expect(vm.isDeadPollingFallbackVisible, isFalse);
    });

    test('refreshPaymentPolling approves immediately when session paid', () async {
      SessionManager().setSessionFromResponse(_sessionJson('sess-paid'));
      final vm = PrePaymentViewModel(
        appSettingsManager: _SeededAppSettingsManager(),
        apiService: FakeApiService(
          fetchSessionResult: {'paymentStatus': 'APPROVED'},
        ),
        sessionManager: SessionManager(),
      );

      await vm.refreshPaymentPolling();
      expect(vm.fcmPaymentPushSuccess, isTrue);
    });

    test('loadPaymentQr reports photo sync failures', () async {
      SessionManager().setSessionFromResponse(_sessionJson('sess-photo-fail'));
      final vm = PrePaymentViewModel(
        appSettingsManager: _SeededAppSettingsManager(),
        apiService: FakeApiService(fetchSessionResult: {}),
        sessionManager: SessionManager(),
      );

      await vm.loadPaymentQr(
        photoForSessionSync: PhotoModel(
          id: 'p1',
          imageFile: XFile.fromData(
            Uint8List.fromList(img.encodeJpg(img.Image(width: 8, height: 8))),
            name: 'test.jpg',
            mimeType: 'image/jpeg',
          ),
          capturedAt: DateTime.utc(2026, 1, 1),
        ),
      );

      expect(vm.paymentInitError, isNotNull);
    });

    test('loadPaymentQr skips duplicate initiate when QR already present', () async {
      SessionManager().setSessionFromResponse(_sessionJson('sess-skip'));
      final api = FakeApiService();
      final vm = PrePaymentViewModel(
        appSettingsManager: _SeededAppSettingsManager(),
        apiService: api,
        sessionManager: SessionManager(),
      );

      await vm.loadPaymentQr();
      final firstCalls = api.initiatePaymentCalls;
      await vm.loadPaymentQr();
      expect(api.initiatePaymentCalls, firstCalls);
    });

    test('payment and session polls handle failed verdicts', () async {
      await _withPollingVm(
        fetchPaymentStatusResult: {'status': 'FAILED'},
        fetchSessionResult: {'paymentStatus': 'FAILED'},
        afterLoad: (vm, async) {
          async.elapse(const Duration(seconds: 3));
          async.flushMicrotasks();
          expect(vm.fcmPaymentPushSuccess, isFalse);
        },
      );
    });

    test('refreshPaymentPolling handles failed session verdict', () async {
      SessionManager().setSessionFromResponse(_sessionJson('sess-fail'));
      final vm = PrePaymentViewModel(
        appSettingsManager: _SeededAppSettingsManager(),
        apiService: FakeApiService(
          fetchSessionResult: {'paymentStatus': 'FAILED'},
        ),
        sessionManager: SessionManager(),
      );

      await vm.refreshPaymentPolling();
      expect(vm.fcmPaymentPushSuccess, isFalse);
    });

    test('onFcmPaymentPush ignores non-terminal payloads', () async {
      final vm = PrePaymentViewModel(
        appSettingsManager: _SeededAppSettingsManager(),
        apiService: FakeApiService(),
      );

      await vm.onFcmPaymentPush(
        PaymentPushPayload(
          type: 'PENDING',
          paymentId: 'p1',
        ),
      );
      expect(vm.fcmPaymentPushSuccess, isNull);
    });

    test('initialAmount and gateway flags reflect settings', () {
      final vm = PrePaymentViewModel(
        appSettingsManager: _SeededAppSettingsManager(
          settings: AppSettingsModel(
            parallelImageCount: 1,
            initialPrice: 250,
            paymentGatewayEnabled: false,
          ),
        ),
        apiService: FakeApiService(),
      );
      expect(vm.initialAmount, 250);
      expect(vm.isPaymentGatewayEnabled, isFalse);
    });

    test('stopPaymentPolling and dispose cancel timers', () async {
      SessionManager().setSessionFromResponse(_sessionJson('sess-dispose'));
      final vm = PrePaymentViewModel(
        appSettingsManager: _SeededAppSettingsManager(),
        apiService: FakeApiService(),
        sessionManager: SessionManager(),
      );

      await vm.loadPaymentQr();
      vm.stopPaymentPolling();
      vm.dispose();
      vm.notifyListeners();
      expect(vm.paymentInitInProgress, isFalse);
    });
  });
}

Future<void> _withPollingVm({
  required Map<String, dynamic>? fetchPaymentStatusResult,
  Map<String, dynamic>? fetchSessionResult,
  required void Function(PrePaymentViewModel vm, FakeAsync async) afterLoad,
}) async {
  fakeAsync((async) {
    SessionManager().setSessionFromResponse(_sessionJson('sess-poll'));
    final vm = PrePaymentViewModel(
      appSettingsManager: _SeededAppSettingsManager(),
      apiService: FakeApiService(
        fetchPaymentStatusResult: fetchPaymentStatusResult,
        fetchSessionResult: fetchSessionResult,
      ),
      sessionManager: SessionManager(),
    );

    vm.loadPaymentQr();
    async.elapse(Duration.zero);
    async.flushMicrotasks();
    afterLoad(vm, async);
  });
}

class _SeededAppSettingsManager extends AppSettingsManager {
  _SeededAppSettingsManager({AppSettingsModel? settings})
      : _seed = settings ??
            AppSettingsModel(
              parallelImageCount: 1,
              initialPrice: AppConstants.kDefaultInitialPrintPrice,
              paymentGatewayEnabled: true,
            ),
        super(
          apiService: FakeApiService(),
          resolveKioskCode: () async => null,
        );

  final AppSettingsModel _seed;

  @override
  AppSettingsModel? get settings => _seed;

  @override
  bool get hasSettings => true;
}

class _ThrowingInitiateApi extends FakeApiService {
  @override
  Future<PaymentInitiateResult> initiatePayment({
    required String sessionId,
    required int amount,
    String type = 'INITIAL',
    String? customerPhone,
    required String fcmToken,
  }) async {
    throw StateError('boom');
  }
}

class _PhotoSyncApi extends FakeApiService {
  var _fetchCount = 0;

  @override
  Future<Map<String, dynamic>?> fetchSession(String sessionId) async {
    fetchSessionCalls++;
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

Map<String, dynamic> _sessionJson(String id) {
  return {
    'id': id,
    'sessionId': id,
    'termsAccepted': true,
    'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
    'attemptsUsed': 0,
    'generatedImages': <dynamic>[],
    'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
  };
}
