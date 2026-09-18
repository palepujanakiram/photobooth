import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/terms_and_conditions/terms_and_conditions_viewmodel.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:photobooth/utils/app_strings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fakes/fake_api_service.dart';
import 'fakes/fake_kiosk_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SessionManager().endCustomerSession();
  });
  test('toggleAgreement updates canSubmit', () {
    final vm = TermsAndConditionsViewModel(
      apiService: FakeApiService(),
      kioskManager: FakeKioskManager(code: 'K1'),
    );
    expect(vm.canSubmit, isFalse);
    vm.toggleAgreement(true);
    expect(vm.canSubmit, isTrue);
    vm.toggleAgreement(false);
    expect(vm.canSubmit, isFalse);
  });

  test('validateAndSetKioskCode rejects empty', () async {
    final vm = TermsAndConditionsViewModel(
      apiService: FakeApiService(),
      kioskManager: FakeKioskManager(),
    );
    final ok = await vm.validateAndSetKioskCode('  ');
    expect(ok, isFalse);
    expect(vm.errorMessage, isNotNull);
  });

  test('validateAndSetKioskCode succeeds when API validates', () async {
    final api = FakeApiService(validateKioskCodeResult: true);
    final km = FakeKioskManager();
    final vm = TermsAndConditionsViewModel(
      apiService: api,
      kioskManager: km,
    );
    final ok = await vm.validateAndSetKioskCode('abc');
    expect(ok, isTrue);
    expect(api.validateKioskCodeCalls, 1);
    expect(km.lastSavedCode, 'ABC');
  });

  test('acceptTermsAndCreateSession requires agreement', () async {
    final vm = TermsAndConditionsViewModel(
      apiService: FakeApiService(),
      kioskManager: FakeKioskManager(),
    );
    final ok = await vm.acceptTermsAndCreateSession(null);
    expect(ok, isFalse);
    expect(vm.errorMessage, contains('agree'));
  });

  test('acceptTermsAndCreateSession stores terms-accepted session', () async {
    final api = FakeApiService(
      sessionResponse: {
        'id': 'sess-terms',
        'expiresAt': DateTime.utc(2027, 1, 1).toIso8601String(),
      },
    );
    final vm = TermsAndConditionsViewModel(
      apiService: api,
      kioskManager: FakeKioskManager(code: 'K1'),
    );
    vm.toggleAgreement(true);
    final ok = await vm.acceptTermsAndCreateSession('K1');
    expect(ok, isTrue);
    expect(vm.errorMessage, isNull);
    expect(SessionManager().sessionId, 'sess-terms');
    expect(SessionManager().hasAcceptedTermsSession, isTrue);
  });

  test('acceptTermsAndCreateSession fills session when API omits fields',
      () async {
    final api = FakeApiService(sessionResponse: const {});
    final vm = TermsAndConditionsViewModel(
      apiService: api,
      kioskManager: FakeKioskManager(),
    );
    vm.toggleAgreement(true);
    final ok = await vm.acceptTermsAndCreateSession(null);
    expect(ok, isTrue);
    expect(SessionManager().hasAcceptedTermsSession, isTrue);
    expect(SessionManager().sessionId, isNotEmpty);
  });

  test('acceptTermsAndCreateSession refuses an already-expired session',
      () async {
    final api = FakeApiService(
      sessionResponse: {
        'id': 'sess-expired',
        'termsAccepted': true,
        'termsAcceptedAt': DateTime.utc(2020, 1, 1).toIso8601String(),
        'expiresAt': DateTime.utc(2020, 1, 2).toIso8601String(),
      },
    );
    final vm = TermsAndConditionsViewModel(
      apiService: api,
      kioskManager: FakeKioskManager(),
    );
    vm.toggleAgreement(true);
    final ok = await vm.acceptTermsAndCreateSession(null);
    expect(ok, isFalse);
    expect(vm.errorMessage, AppStrings.termsSessionCreateFailed);
    expect(SessionManager().hasAcceptedTermsSession, isFalse);
  });
}
