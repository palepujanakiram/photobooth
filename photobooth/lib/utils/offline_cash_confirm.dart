import 'package:uuid/uuid.dart';

import '../models/payment_mode.dart';
import '../services/local_kiosk_settlement.dart';
import '../services/local_kiosk_store.dart';
import '../services/session_manager.dart';
import 'app_strings.dart';
import 'exceptions.dart';

/// Result of recording cash collected outside the app for an offline session.
class OfflineCashConfirmResult {
  const OfflineCashConfirmResult({
    required this.paymentId,
    required this.sessionId,
    required this.amountRupees,
  });

  final String paymentId;
  final String sessionId;
  final int amountRupees;
}

/// Writes CASH approval to the on-device ledger and marks the guest session paid.
///
/// Used when Fly never saw the session (pure offline) so staff confirm must
/// happen on the same kiosk without leaving Pay.
Future<OfflineCashConfirmResult> settleOfflineCashForCurrentSession({
  required int amountRupees,
  SessionManager? sessionManager,
  LocalKioskStore? store,
  String Function()? newPaymentId,
}) async {
  final sm = sessionManager ?? SessionManager();
  final sid = sm.sessionId?.trim() ?? '';
  if (sid.isEmpty) {
    throw ApiException(AppStrings.sessionPhotoSyncNoSession);
  }

  final ledger = store ?? LocalKioskStore.instance;
  if (ledger == null) {
    throw ApiException(AppStrings.offlineCashConfirmNoLedger);
  }

  final paymentId = (newPaymentId ?? _uuidV4)().trim();
  if (paymentId.isEmpty) {
    throw ApiException(AppStrings.offlineCashConfirmFailed);
  }

  final amount = amountRupees < 0 ? 0 : amountRupees;
  await LocalKioskSettlement(store: ledger).recordApprovedPayment(
    paymentId: paymentId,
    sessionId: sid,
    amount: amount,
    paymentMode: PaymentMode.cash.apiValue,
  );

  return OfflineCashConfirmResult(
    paymentId: paymentId,
    sessionId: sid,
    amountRupees: amount,
  );
}

String _uuidV4() => const Uuid().v4();
