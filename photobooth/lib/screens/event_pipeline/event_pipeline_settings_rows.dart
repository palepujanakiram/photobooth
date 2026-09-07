import 'package:flutter/material.dart';

import '../../models/event_pipeline/event_pipeline_settings.dart';
import '../../views/widgets/app_colors.dart';

/// Collapsible header showing whether the pipeline is on at a glance.
class EventPipelineHeaderRow extends StatelessWidget {
  const EventPipelineHeaderRow({
    super.key,
    required this.appColors,
    required this.on,
    required this.expanded,
    required this.onToggleExpanded,
  });

  final AppColors appColors;
  final bool on;
  final bool expanded;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggleExpanded,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Event pipeline',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: appColors.textColor,
                ),
              ),
            ),
            Text(
              on ? 'On' : 'Off',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: on ? appColors.successColor : appColors.secondaryTextColor,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 20,
              color: appColors.secondaryTextColor,
            ),
          ],
        ),
      ),
    );
  }
}

/// One labelled switch with a supporting line of detail.
class EventPipelineSwitchRow extends StatelessWidget {
  const EventPipelineSwitchRow({
    super.key,
    required this.appColors,
    required this.label,
    required this.detail,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final AppColors appColors;
  final String label;
  final String detail;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: appColors.textColor,
                  ),
                ),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 11,
                    color: appColors.secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}

/// Copies stepper, clamped to a range a dye-sub roll can sensibly serve.
class EventPipelineCopiesRow extends StatelessWidget {
  const EventPipelineCopiesRow({
    super.key,
    required this.appColors,
    required this.copies,
    required this.onChanged,
    this.enabled = true,
  });

  static const int maxCopies = 10;

  final AppColors appColors;
  final int copies;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Copies per photo',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: appColors.textColor,
              ),
            ),
          ),
          IconButton(
            iconSize: 20,
            onPressed:
                enabled && copies > 1 ? () => onChanged(copies - 1) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text(
            '$copies',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: appColors.textColor,
            ),
          ),
          IconButton(
            iconSize: 20,
            onPressed: enabled && copies < maxCopies
                ? () => onChanged(copies + 1)
                : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}

/// Shows the chain a photo will run through, exactly as it will be frozen onto
/// each item at selection time. This is the operator's confirmation that the
/// switches above add up to what they expect.
class EventPipelineChainPreview extends StatelessWidget {
  const EventPipelineChainPreview({
    super.key,
    required this.appColors,
    required this.steps,
    required this.copies,
    required this.printSize,
  });

  final AppColors appColors;
  final List<String> steps;
  final int copies;
  final String printSize;

  static String labelFor(String step) {
    switch (step) {
      case EventPipelineStep.ai:
        return 'AI';
      case EventPipelineStep.frame:
        return 'Frame';
      case EventPipelineStep.print:
        return 'Print';
      default:
        return step;
    }
  }

  /// Human summary of the chain, e.g. `AI → Frame → Print 4x6 · 2 copies`.
  static String describe(List<String> steps, int copies, String printSize) {
    if (steps.isEmpty) return 'Nothing will run — imports are stored only.';
    final parts = steps.map(labelFor).toList();
    final buffer = StringBuffer(parts.join(' → '));
    if (steps.contains(EventPipelineStep.print)) {
      buffer.write(' $printSize');
      buffer.write(copies == 1 ? ' · 1 copy' : ' · $copies copies');
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: appColors.surfaceColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Each photo will run',
              style: TextStyle(
                fontSize: 11,
                color: appColors.secondaryTextColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              describe(steps, copies, printSize),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: appColors.textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Clears every local override and returns to inheriting the event's config.
class EventPipelineResetRow extends StatelessWidget {
  const EventPipelineResetRow({
    super.key,
    required this.appColors,
    required this.onReset,
    this.enabled = true,
  });

  final AppColors appColors;
  final bool enabled;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: enabled ? onReset : null,
        child: const Text(
          'Reset to event defaults',
          style: TextStyle(fontSize: 12),
        ),
      ),
    );
  }
}
