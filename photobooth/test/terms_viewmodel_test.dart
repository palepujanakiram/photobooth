import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/terms_and_conditions/terms_and_conditions_viewmodel.dart';
import 'fakes/fake_api_service.dart';
import 'fakes/fake_kiosk_manager.dart';

void main() {
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
}
