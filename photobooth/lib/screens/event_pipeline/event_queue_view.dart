import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/app_strings.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_scaffold.dart';
import '../event_station/event_station_chrome_view_widgets.dart';
import 'event_queue_viewmodel.dart';

/// Shows every photo the pipeline is holding, and where each one has got to.
///
/// The missing half of the import flow: without it an operator sees a count and
/// nothing else, so a queue that has stalled looks exactly like one that has
/// finished — and imported photos appear to have vanished.
class EventQueueScreen extends StatelessWidget {
  const EventQueueScreen({super.key, this.viewModel});

  final EventQueueViewModel? viewModel;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<EventQueueViewModel>(
      create: (_) => (viewModel ?? EventQueueViewModel())..start(),
      child: AppScaffold(
        title: AppStrings.eventQueueTitle,
        showBackButton: true,
        child: EventStationBoundShell(
          child: Consumer<EventQueueViewModel>(
            builder: (context, vm, _) => _QueueBody(vm: vm),
          ),
        ),
      ),
    );
  }
}

class _QueueBody extends StatelessWidget {
  const _QueueBody({required this.vm});

  final EventQueueViewModel vm;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (vm.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.photo_library_outlined,
                  size: 56, color: colors.secondaryTextColor),
              const SizedBox(height: 16),
              Text(
                'Nothing imported yet',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: colors.textColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Photos imported from a card appear here with their progress.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.secondaryTextColor),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            vm.stats.summary,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colors.textColor,
            ),
          ),
          if (vm.stats.printPaused)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Print queue paused — check ribbon, paper and cover.',
                style: TextStyle(fontSize: 11, color: colors.warningColor),
              ),
            ),
          const SizedBox(height: 8),
          _QueueFilterBar(vm: vm, colors: colors),
          const SizedBox(height: 8),
          Expanded(
            child: vm.isFilteredEmpty
                ? Center(
                    child: Text(
                      'No photos are ${QueueFilter.labelFor(vm.filter).toLowerCase()}.',
                      style: TextStyle(color: colors.secondaryTextColor),
                    ),
                  )
                : GridView.builder(
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.78,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
                    itemCount: vm.visibleEntries.length,
                    itemBuilder: (context, i) => _QueueTile(
                      entry: vm.visibleEntries[i],
                      colors: colors,
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          _QueueActions(vm: vm),
        ],
      ),
    );
  }
}

/// Status chips with live counts.
///
/// Only stages that hold photos get a chip, so an AI-off event never shows a
/// permanently empty "AI" filter.
class _QueueFilterBar extends StatelessWidget {
  const _QueueFilterBar({required this.vm, required this.colors});

  final EventQueueViewModel vm;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final options = vm.filterOptions;
    if (options.length <= 1) return const SizedBox.shrink();
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final option = options[i];
          return ChoiceChip(
            label: Text('${option.label} ${option.count}'),
            labelStyle: const TextStyle(fontSize: 12),
            selected: vm.filter == option.value,
            onSelected: (_) => vm.setFilter(option.value),
          );
        },
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({required this.entry, required this.colors});

  final QueueEntry entry;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final file = entry.thumbnailFile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: file == null
                ? Container(
                    color: colors.cardBackgroundColor,
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: colors.secondaryTextColor,
                    ),
                  )
                // Decoded small on purpose: the derivative is 2880px wide, and
                // decoding dozens at full size would blow the heap the same way
                // the old import tray did.
                : Image.file(
                    file,
                    fit: BoxFit.cover,
                    cacheWidth: 240,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => Container(
                      color: colors.cardBackgroundColor,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          entry.item.originalFilename ?? entry.item.id,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: colors.textColor),
        ),
        Text(
          entry.stageLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: entry.isFailed
                ? colors.errorColor
                : entry.isDone
                    ? colors.successColor
                    : colors.secondaryTextColor,
          ),
        ),
      ],
    );
  }
}

class _QueueActions extends StatelessWidget {
  const _QueueActions({required this.vm});

  final EventQueueViewModel vm;

  @override
  Widget build(BuildContext context) {
    final stuck = vm.stuckOnAi.length;
    return Wrap(
      spacing: 8,
      alignment: WrapAlignment.center,
      children: [
        if (vm.hasFailed)
          TextButton(
            onPressed: vm.isBusy ? null : vm.retryFailed,
            child: Text('Retry ${vm.failedCount} failed'),
          ),
        if (stuck > 0)
          TextButton(
            onPressed: vm.isBusy
                ? null
                : () async {
                    final n = await vm.skipAiForStuck();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Skipped AI on $n photos')),
                    );
                  },
            child: Text('Skip AI ($stuck)'),
          ),
      ],
    );
  }
}
