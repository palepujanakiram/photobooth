import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/local_kiosk_store.dart';
import 'package:photobooth/services/offline_operator_pin_store.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:photobooth/utils/offline_cash_confirm.dart';
import 'package:photobooth/utils/payment_workflow_helpers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    OfflineOperatorPinStore.resetCacheForTests();
    SessionManager().clearSession();
    LocalKioskStore.resetInstance();
  });

  test('default operator PIN verifies', () async {
    expect(await OfflineOperatorPinStore.verifyPin('2468'), isTrue);
    expect(await OfflineOperatorPinStore.verifyPin('0000'), isFalse);
  });

  test('setPin adds local pin; master 2468 still works', () async {
    await OfflineOperatorPinStore.setPin('9999');
    expect(await OfflineOperatorPinStore.verifyPin('9999'), isTrue);
    expect(await OfflineOperatorPinStore.verifyPin('2468'), isTrue);
    expect(await OfflineOperatorPinStore.verifyPin('0000'), isFalse);
  });

  test('syncServerPins accepts staff pins from settings', () async {
    await OfflineOperatorPinStore.syncServerPins(['1357', 'bad', '12']);
    expect(await OfflineOperatorPinStore.verifyPin('1357'), isTrue);
    expect(await OfflineOperatorPinStore.verifyPin('2468'), isTrue);
    expect(await OfflineOperatorPinStore.verifyPin('12'), isFalse);
  });

  test('shouldSkipOfflinePayCollect only when offline and payments off', () {
    expect(
      shouldSkipOfflinePayCollect(
        paymentsEnabled: false,
        sessionOffline: true,
      ),
      isTrue,
    );
    expect(
      shouldSkipOfflinePayCollect(
        paymentsEnabled: true,
        sessionOffline: true,
      ),
      isFalse,
    );
    expect(
      shouldSkipOfflinePayCollect(
        paymentsEnabled: false,
        sessionOffline: false,
      ),
      isFalse,
    );
  });

  test('settleOfflineCashForCurrentSession records ledger payment', () async {
    final dir = await Directory.systemTemp.createTemp('fz_cash_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final store = await LocalKioskStore.init(
      resolveDirectory: () async => dir,
    );
    SessionManager().setSessionFromResponse({
      'id': 'sess-cash-1',
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': <dynamic>[],
      'expiresAt': DateTime.utc(2026, 12, 31).toIso8601String(),
      'offline': true,
    });

    final result = await settleOfflineCashForCurrentSession(
      amountRupees: 250,
      store: store,
      newPaymentId: () => 'pay-cash-1',
    );
    expect(result.paymentId, 'pay-cash-1');
    expect(result.amountRupees, 250);
    final payments = await store.paymentsForSession('sess-cash-1');
    expect(payments, hasLength(1));
    expect(payments.first.payload['paymentMode'], 'CASH');
    expect(payments.first.payload['status'], 'APPROVED');
    final session = await store.getSession('sess-cash-1');
    expect(session?['paymentStatus'], 'APPROVED');
  });
}
