import 'package:flutter/cupertino.dart';

import '../../services/local_kiosk_models.dart';
import '../../utils/app_strings.dart';
import '../../views/widgets/app_colors.dart';

/// Pending outbox counter + Sync button for splash manage mode.
class SplashOutboxSyncPanel extends StatelessWidget {
  const SplashOutboxSyncPanel({
    super.key,
    required this.appColors,
    required this.counts,
    required this.syncing,
    required this.completedThisRun,
    required this.onSyncPressed,
    this.enabled = true,
  });

  final AppColors appColors;
  final KioskOutboxSyncCounts counts;
  final bool syncing;
  final int completedThisRun;
  final VoidCallback? onSyncPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final open = counts.open;
    final status = syncing
        ? AppStrings.splashSyncProgress(completedThisRun, open)
        : (open == 0
            ? AppStrings.splashSyncCaughtUp
            : AppStrings.splashSyncPending(open, counts.failed));

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: appColors.cardBackgroundColor.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: appColors.dividerColor.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  syncing
                      ? CupertinoIcons.arrow_2_circlepath
                      : (open == 0
                          ? CupertinoIcons.checkmark_seal
                          : CupertinoIcons.cloud_upload),
                  size: 18,
                  color: open == 0 && !syncing
                      ? CupertinoColors.activeGreen
                      : appColors.secondaryTextColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: appColors.textColor,
                    ),
                  ),
                ),
                Text(
                  '$open',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: open == 0
                        ? CupertinoColors.activeGreen
                        : CupertinoColors.activeOrange,
                  ),
                ),
              ],
            ),
            if (syncing) ...[
              const SizedBox(height: 10),
              const CupertinoActivityIndicator(radius: 10),
            ],
            const SizedBox(height: 10),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 12),
              color: CupertinoColors.activeGreen,
              borderRadius: BorderRadius.circular(12),
              onPressed: (!enabled || syncing) ? null : onSyncPressed,
              child: Text(
                syncing
                    ? AppStrings.splashSyncingButton
                    : AppStrings.splashSyncNowButton,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: CupertinoColors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
