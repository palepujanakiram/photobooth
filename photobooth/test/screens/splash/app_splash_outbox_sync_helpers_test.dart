import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/splash/app_splash_outbox_sync_helpers.dart';
import 'package:photobooth/services/kiosk_outbox_worker.dart';
import 'package:photobooth/utils/app_strings.dart';

void main() {
  test('splashOutboxSyncResultMessage for caught up vs remaining', () {
    expect(
      splashOutboxSyncResultMessage(
        const KioskOutboxDrainResult(completed: 3, remaining: 0, failed: 0),
      ),
      AppStrings.splashSyncCompleteToast,
    );
    expect(
      splashOutboxSyncResultMessage(
        const KioskOutboxDrainResult(completed: 1, remaining: 4, failed: 1),
      ),
      AppStrings.splashSyncPartialToast(4),
    );
  });
}
