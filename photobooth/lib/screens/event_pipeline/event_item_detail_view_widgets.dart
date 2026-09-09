import 'package:flutter/material.dart';

import '../../views/widgets/app_colors.dart';
import 'event_item_detail_viewmodel.dart';

/// Source, AI and framed side by side, each with its dimensions.
///
/// Side by side is how an operator answers "did the frame come out right"
/// without walking to the printer — and the dimensions are how they spot a
/// portrait shot that came out landscape.
class ItemRenditionStrip extends StatelessWidget {
  const ItemRenditionStrip({
    super.key,
    required this.appColors,
    required this.renditions,
  });

  final AppColors appColors;
  final List<ItemRendition> renditions;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in renditions) ...[
          Expanded(child: _tile(r)),
          if (r != renditions.last) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _tile(ItemRendition rendition) {
    final file = rendition.file;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          rendition.label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: appColors.secondaryTextColor,
          ),
        ),
        const SizedBox(height: 4),
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: file == null
                ? Container(
                    color: appColors.cardBackgroundColor,
                    child: Center(
                      child: Text(
                        // A stage that never ran and a stage that failed look
                        // different here, which is the point of showing all
                        // three rather than only what exists.
                        'Not produced',
                        style: TextStyle(
                          fontSize: 10,
                          color: appColors.secondaryTextColor,
                        ),
                      ),
                    ),
                  )
                : Image.file(
                    file,
                    fit: BoxFit.cover,
                    // These are print derivatives; decode them small.
                    cacheWidth: 400,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => Container(
                      color: appColors.cardBackgroundColor,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          rendition.dimensions ?? '—',
          style: TextStyle(fontSize: 10, color: appColors.secondaryTextColor),
        ),
      ],
    );
  }
}

/// Stage, chain, error, source card and shot time.
class ItemFactsTable extends StatelessWidget {
  const ItemFactsTable({
    super.key,
    required this.appColors,
    required this.vm,
  });

  final AppColors appColors;
  final EventItemDetailViewModel vm;

  @override
  Widget build(BuildContext context) {
    final shot = vm.shotAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row('Stage', vm.stageLabel),
        _row('Chain', vm.chainLabel),
        if (vm.failureReason != null)
          // The real error text, not a category: a category is not something an
          // operator can act on.
          _row('Error', vm.failureReason!, tone: appColors.errorColor),
        if (vm.sourceLabel != null) _row('Source', vm.sourceLabel!),
        if (shot != null) _row('Shot', _formatShot(shot)),
      ],
    );
  }

  Widget _row(String label, String value, {Color? tone}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: appColors.secondaryTextColor,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tone ?? appColors.textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const List<String> _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _formatShot(DateTime t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '${t.day} ${_months[t.month - 1]} ${t.year}, $hh:$mm';
  }
}

/// Retry · Skip AI · Reprint · Remove, each shown only when it applies.
class ItemDetailActions extends StatelessWidget {
  const ItemDetailActions({
    super.key,
    required this.appColors,
    required this.vm,
    required this.onRemoved,
  });

  final AppColors appColors;
  final EventItemDetailViewModel vm;
  final VoidCallback onRemoved;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      alignment: WrapAlignment.center,
      children: [
        if (vm.canRetry)
          TextButton(
            onPressed: vm.isBusy ? null : vm.retry,
            child: const Text('Retry'),
          ),
        if (vm.canSkipAi)
          TextButton(
            onPressed: vm.isBusy ? null : vm.skipAi,
            child: const Text('Skip AI'),
          ),
        if (vm.canReprint)
          TextButton(
            onPressed: vm.isBusy ? null : vm.reprint,
            child: const Text('Reprint'),
          ),
        TextButton(
          onPressed: vm.isBusy
              ? null
              : () async {
                  await vm.remove();
                  onRemoved();
                },
          child: const Text('Remove'),
        ),
      ],
    );
  }
}
