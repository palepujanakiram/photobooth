import '../../services/kiosk_outbox_worker.dart';
import '../../utils/app_strings.dart';

/// Toast copy after a manual splash Sync finishes.
String splashOutboxSyncResultMessage(KioskOutboxDrainResult result) {
  if (result.isCaughtUp) return AppStrings.splashSyncCompleteToast;
  return AppStrings.splashSyncPartialToast(result.remaining);
}
