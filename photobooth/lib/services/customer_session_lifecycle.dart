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
///
/// When [onlyIfId] is set, a session created after this end was scheduled
/// (Start again → new guest accepted terms) is left intact.
Future<void> endPhotoboothCustomerSession({String? onlyIfId}) async {
  final ended = await SessionManager().endCustomerSession(onlyIfId: onlyIfId);
  if (!ended) return;
  await PaymentPushCoordinator.instance.resetForNextCustomer();
  unawaited(cleanupGuestTempImagesIfIdle());
}

/// Deletes capture temp files only when no guest session is active, so a
/// delayed wipe cannot remove the next guest's photos.
Future<void> cleanupGuestTempImagesIfIdle() async {
  if (SessionManager().hasSession) return;
  await FileHelper.cleanupTempImages();
}

/// Same as [endPhotoboothCustomerSession] but logs and swallows errors so navigation
/// still runs (e.g. thank-you exit).
Future<void> endPhotoboothCustomerSessionLogged(
  String context, {
  String? onlyIfId,
}) async {
  try {
    await endPhotoboothCustomerSession(onlyIfId: onlyIfId);
  } catch (e, st) {
    AppLogger.error(
      'endPhotoboothCustomerSession failed ($context)',
      error: e,
      stackTrace: st,
    );
  }
}
