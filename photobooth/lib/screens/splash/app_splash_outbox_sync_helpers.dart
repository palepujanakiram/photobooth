import 'package:flutter/foundation.dart' show kIsWeb;

import '../../services/kiosk_outbox_worker.dart';
import '../../utils/app_strings.dart';

/// Toast copy after a manual splash Sync finishes.
String splashOutboxSyncResultMessage(KioskOutboxDrainResult result) {
  if (result.isCaughtUp) return AppStrings.splashSyncCompleteToast;
  return AppStrings.splashSyncPartialToast(result.remaining);
}

/// Offline ledger drain needs SQLite + [KioskOutboxWorker] (native booth only).
bool splashOutboxSyncAvailable({
  bool isWeb = kIsWeb,
  bool? hasWorker,
}) {
  if (isWeb) return false;
  return hasWorker ?? KioskOutboxWorker.instance != null;
}

/// Copy when Sync is tapped without a native outbox worker (browser kiosk).
String splashOutboxSyncUnavailableMessage() =>
    AppStrings.splashSyncUnavailableInBrowser;
