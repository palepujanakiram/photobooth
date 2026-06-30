import 'dart:async' show unawaited;

import '../utils/logger.dart';
import 'file_helper.dart';
import 'payment_push_coordinator.dart';
import 'session_manager.dart';

/// Single chokepoint when a **customer** journey ends on the kiosk: thank-you,
/// privacy wipe, kiosk reprovision, or explicit session delete.
///
/// Resets payment FCM dedup/queue + disk pending store and clears local session
/// (memory + SharedPreferences). **Await** before navigation so prefs can flush.
Future<void> endPhotoboothCustomerSession() async {
  await PaymentPushCoordinator.instance.resetForNextCustomer();
  await SessionManager().endCustomerSession();
  unawaited(FileHelper.cleanupTempImages());
}

/// Same as [endPhotoboothCustomerSession] but logs and swallows errors so navigation
/// still runs (e.g. thank-you exit).
Future<void> endPhotoboothCustomerSessionLogged(String context) async {
  try {
    await endPhotoboothCustomerSession();
  } catch (e, st) {
    AppLogger.error(
      'endPhotoboothCustomerSession failed ($context)',
      error: e,
      stackTrace: st,
    );
  }
}
