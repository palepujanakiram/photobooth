import 'package:flutter/material.dart';

import '../../models/event_pipeline/event_readiness.dart';
import '../../models/event_pipeline/media_item.dart';
import '../../services/event_pipeline/event_pipeline_stats.dart';
import '../../views/widgets/app_colors.dart';

/// Event name and tagline, over the readiness block.
class EventHubHeader extends StatelessWidget {
  const EventHubHeader({
    super.key,
    required this.appColors,
    required this.name,
    required this.tagline,
  });

  final AppColors appColors;
  final String? name;
  final String? tagline;

  @override
  Widget build(BuildContext context) {
    final title = name?.trim() ?? '';
    final subtitle = tagline?.trim() ?? '';
    if (title.isEmpty && subtitle.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: appColors.textColor,
              ),
            ),
          if (subtitle.isNotEmpty)
            Text(
              subtitle.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.2,
                color: appColors.secondaryTextColor,
              ),
            ),
        ],
      ),
    );
  }
}

/// The readiness block: one line per thing that can quietly not be ready.
class EventHubReadinessBlock extends StatelessWidget {
  const EventHubReadinessBlock({
    super.key,
    required this.appColors,
    required this.headline,
    required this.rows,
    required this.onExplain,
    this.onOpenSettings,
    this.onRecheck,
    this.isChecking = false,
  });

  final AppColors appColors;
  final String headline;
  final List<ReadinessRow> rows;

  /// Opens event settings. Lives on this header because the hub has no app
  /// bar — it is the event's root and a title bar would carry a back arrow.
  final VoidCallback? onOpenSettings;

  /// Looks for the camera and printer again.
  ///
  /// Always available rather than only on a red row: the hub stops probing once
  /// its window closes, so a camera unplugged afterwards reads connected until
  /// someone asks again. A stale green row is exactly the case that needs this.
  final VoidCallback? onRecheck;

  final bool isChecking;

  /// Called when an amber or red row is tapped. Green rows are not tappable —
  /// there is nothing to explain, and a tap that does nothing teaches an
  /// operator that tapping never helps.
  final void Function(ReadinessRow row) onExplain;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: appColors.cardBackgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: appColors.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  headline,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: appColors.textColor,
                  ),
                ),
              ),
              if (onRecheck != null)
                InkWell(
                  onTap: isChecking ? null : onRecheck,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.refresh,
                          size: 16,
                          color: appColors.secondaryTextColor,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          isChecking ? 'Checking…' : 'Recheck',
                          style: TextStyle(
                            fontSize: 11,
                            color: appColors.secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (onOpenSettings != null)
                InkWell(
                  onTap: onOpenSettings,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.settings_outlined,
                      size: 20,
                      color: appColors.secondaryTextColor,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (final row in rows)
            EventHubReadinessRow(
              appColors: appColors,
              row: row,
              onTap: row.isActionable ? () => onExplain(row) : null,
            ),
        ],
      ),
    );
  }
}

class EventHubReadinessRow extends StatelessWidget {
  const EventHubReadinessRow({
    super.key,
    required this.appColors,
    required this.row,
    this.onTap,
  });

  final AppColors appColors;
  final ReadinessRow row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tone = toneColor(appColors, row.tone);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(toneIcon(row.tone), size: 16, color: tone),
            const SizedBox(width: 8),
            SizedBox(
              width: 76,
              child: Text(
                row.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: appColors.textColor,
                ),
              ),
            ),
            Expanded(
              child: Text(
                row.detail,
                style: TextStyle(
                  fontSize: 13,
                  color: row.tone == ReadinessTone.ok
                      ? appColors.secondaryTextColor
                      : tone,
                ),
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.info_outline,
                size: 15,
                color: appColors.secondaryTextColor,
              ),
          ],
        ),
      ),
    );
  }

  static Color toneColor(AppColors colors, ReadinessTone tone) {
    switch (tone) {
      case ReadinessTone.ok:
        return colors.successColor;
      case ReadinessTone.warn:
        return colors.warningColor;
      case ReadinessTone.blocked:
        return colors.errorColor;
    }
  }

  static IconData toneIcon(ReadinessTone tone) {
    switch (tone) {
      case ReadinessTone.ok:
        return Icons.check;
      case ReadinessTone.warn:
        return Icons.warning_amber_outlined;
      case ReadinessTone.blocked:
        return Icons.error_outline;
    }
  }
}

/// One tappable counter. Tapping opens the queue filtered to that stage.
class EventHubCounter extends StatelessWidget {
  const EventHubCounter({
    super.key,
    required this.appColors,
    required this.label,
    required this.value,
    required this.onTap,
    this.alarm = false,
  });

  final AppColors appColors;
  final String label;
  final int value;
  final VoidCallback onTap;

  /// Failures are red when non-zero and never hidden.
  final bool alarm;

  @override
  Widget build(BuildContext context) {
    final highlight = alarm && value > 0;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Text(
                '$value',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color:
                      highlight ? appColors.errorColor : appColors.textColor,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.8,
                  color: highlight
                      ? appColors.errorColor
                      : appColors.secondaryTextColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The four counters, each opening the queue filtered to itself.
class EventHubCounterRow extends StatelessWidget {
  const EventHubCounterRow({
    super.key,
    required this.appColors,
    required this.stats,
    required this.onOpenFiltered,
  });

  final AppColors appColors;
  final EventPipelineStats stats;
  final void Function(String stage) onOpenFiltered;

  /// Matches `QueueFilter.working` — the three in-flight stages the WORKING
  /// counter collapses into one number. A literal rather than an import so the
  /// widget layer does not depend on a view model.
  static const String workingFilter = 'WORKING';

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        EventHubCounter(
          appColors: appColors,
          label: 'QUEUED',
          value: stats.queued,
          onTap: () => onOpenFiltered(MediaStage.queued),
        ),
        EventHubCounter(
          appColors: appColors,
          label: 'WORKING',
          value: stats.ai + stats.framing + stats.printing,
          onTap: () => onOpenFiltered(workingFilter),
        ),
        EventHubCounter(
          appColors: appColors,
          label: 'DONE',
          value: stats.done,
          onTap: () => onOpenFiltered(MediaStage.done),
        ),
        EventHubCounter(
          appColors: appColors,
          label: 'FAILED',
          value: stats.failed,
          alarm: true,
          onTap: () => onOpenFiltered(MediaStage.failed),
        ),
      ],
    );
  }
}

/// An action with its reason printed on it when it is unavailable.
///
/// The reason goes **on** the button rather than being a silent grey-out: an
/// operator who taps a dead control and gets nothing has learnt nothing.
class EventHubAction extends StatelessWidget {
  const EventHubAction({
    super.key,
    required this.appColors,
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.disabledReason,
  });

  final AppColors appColors;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final reason = disabledReason?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          onPressed: enabled ? onPressed : null,
          child: Text(label),
        ),
        if (!enabled && reason.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              reason,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: appColors.secondaryTextColor,
              ),
            ),
          ),
      ],
    );
  }
}
