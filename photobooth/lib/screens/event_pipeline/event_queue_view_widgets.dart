import 'package:flutter/material.dart';

import '../../views/widgets/app_colors.dart';
import 'event_queue_viewmodel.dart';

/// Live processing indicator plus the one control that holds the queue.
///
/// Replaces "Run now" rather than renaming it. The queue already runs
/// continuously — frame and print tick every three seconds — so a Run now
/// button implied the opposite, that work waits for a human, and it lied about
/// scope by draining only the local stages while items sat at AI.
///
/// What an operator actually needs is the reverse: a way to **stop**. Ribbon
/// change, paper reload, moving the printer — all want processing held and then
/// resumed (spec §7).
class QueueRunBar extends StatelessWidget {
  const QueueRunBar({
    super.key,
    required this.appColors,
    required this.vm,
  });

  final AppColors appColors;
  final EventQueueViewModel vm;

  @override
  Widget build(BuildContext context) {
    final paused = vm.isPaused;
    return Row(
      children: [
        Icon(
          paused
              ? Icons.pause_circle_outline
              : vm.isProcessing
                  ? Icons.play_circle_outline
                  : Icons.check_circle_outline,
          size: 18,
          color: paused ? appColors.warningColor : appColors.successColor,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            paused ? 'Paused' : vm.stats.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: paused ? appColors.warningColor : appColors.textColor,
            ),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: vm.isBusy ? null : () => vm.setPaused(!paused),
          child: Text(paused ? 'Resume' : 'Pause'),
        ),
      ],
    );
  }
}

/// The last tile of a page: how many more there are, and a tap to fetch them.
///
/// Shown as well as the scroll trigger because a scroll that has not quite
/// reached the threshold otherwise looks like the end of the list.
class QueueLoadMoreTile extends StatelessWidget {
  const QueueLoadMoreTile({
    super.key,
    required this.appColors,
    required this.remaining,
    required this.onTap,
  });

  final AppColors appColors;
  final int remaining;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: appColors.cardBackgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: appColors.dividerColor),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.expand_more, color: appColors.secondaryTextColor),
              const SizedBox(height: 4),
              Text(
                remaining > 0 ? 'Load $remaining more' : 'Load more',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: appColors.secondaryTextColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The selection-mode action bar.
///
/// Nothing acts on everything: an action appears only when it is valid for what
/// is ticked. `All` and `None` are there for the case where the whole filter
/// genuinely is the target — filter to `Failed`, tap `All`, `Retry` — which
/// keeps the bulk case to three taps without making it the default.
class QueueSelectionActions extends StatelessWidget {
  const QueueSelectionActions({
    super.key,
    required this.appColors,
    required this.vm,
  });

  final AppColors appColors;
  final EventQueueViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${vm.selectedCount} selected',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: appColors.textColor,
                ),
              ),
            ),
            TextButton(onPressed: vm.selectAllLoaded, child: const Text('All')),
            TextButton(onPressed: vm.selectNone, child: const Text('None')),
            IconButton(
              tooltip: 'Cancel',
              icon: const Icon(Icons.close, size: 20),
              onPressed: vm.exitSelection,
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          alignment: WrapAlignment.center,
          children: [
            if (vm.canRetrySelected)
              _action(context, 'Retry', vm.retrySelected, 'Retried'),
            if (vm.canSkipAiSelected)
              _action(context, 'Skip AI', vm.skipAiSelected, 'Skipped AI on'),
            if (vm.canReprintSelected)
              _action(context, 'Reprint', vm.reprintSelected, 'Queued'),
            if (vm.canRemoveSelected)
              _action(context, 'Remove', vm.removeSelected, 'Removed'),
          ],
        ),
      ],
    );
  }

  Widget _action(
    BuildContext context,
    String label,
    Future<int> Function() run,
    String verb,
  ) {
    return TextButton(
      onPressed: vm.isBusy
          ? null
          : () async {
              final n = await run();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$verb $n photos')),
              );
            },
      child: Text(label),
    );
  }
}
