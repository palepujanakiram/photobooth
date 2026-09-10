import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/event_pipeline/media_item.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_scaffold.dart';
import '../event_station/event_station_chrome_view_widgets.dart';
import 'event_queue_view_widgets.dart';
import 'event_queue_viewmodel.dart';

/// Shows every photo the pipeline is holding, and where each one has got to.
///
/// The missing half of the import flow: without it an operator sees a count and
/// nothing else, so a queue that has stalled looks exactly like one that has
/// finished — and imported photos appear to have vanished.
class EventQueueScreen extends StatelessWidget {
  const EventQueueScreen({super.key, this.viewModel, this.initialFilter});

  final EventQueueViewModel? viewModel;

  /// Stage to open filtered to, from the hub's counters.
  final String? initialFilter;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<EventQueueViewModel>(
      create: (_) =>
          (viewModel ?? EventQueueViewModel(initialFilter: initialFilter))
            ..start(),
      child: AppScaffold(
        title: AppStrings.eventQueueTitle,
        showBackButton: true,
        actions: [
          Consumer<EventQueueViewModel>(
            builder: (context, vm, _) => vm.selectionMode || vm.isEmpty
                ? const SizedBox.shrink()
                : TextButton(
                    onPressed: vm.enterSelection,
                    child: const Text('Select'),
                  ),
          ),
        ],
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
          QueueRunBar(appColors: colors, vm: vm),
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
          _QueueSourceBar(vm: vm, colors: colors),
          const SizedBox(height: 8),
          Expanded(
            child: vm.isFilteredEmpty
                ? Center(
                    child: Text(
                      'No photos are ${QueueFilter.labelFor(vm.filter).toLowerCase()}.',
                      style: TextStyle(color: colors.secondaryTextColor),
                    ),
                  )
                : _QueueGrid(vm: vm, colors: colors),
          ),
          const SizedBox(height: 8),
          if (vm.selectionMode)
            QueueSelectionActions(appColors: colors, vm: vm)
          else
            _QueueActions(vm: vm),
        ],
      ),
    );
  }
}

/// The paged grid, with load-more on scroll.
///
/// Pagination is not a preference: a 3,000-photo event would otherwise build
/// 3,000 tiles, and on the Amlogic box that is the difference between a screen
/// that scrolls and one that looks broken.
class _QueueGrid extends StatefulWidget {
  const _QueueGrid({required this.vm, required this.colors});

  final EventQueueViewModel vm;
  final AppColors colors;

  @override
  State<_QueueGrid> createState() => _QueueGridState();
}

class _QueueGridState extends State<_QueueGrid> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    // A screenful of headroom, so the next page is already in when the operator
    // reaches the bottom rather than after it.
    if (position.pixels >= position.maxScrollExtent - 600) {
      unawaited(widget.vm.loadMore());
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final entries = vm.visibleEntries;
    return GridView.builder(
      controller: _controller,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.78,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: entries.length + (vm.hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= entries.length) {
          return QueueLoadMoreTile(
            appColors: widget.colors,
            remaining: vm.totalInFilter - entries.length,
            onTap: vm.loadMore,
          );
        }
        final entry = entries[i];
        return _QueueTile(
          entry: entry,
          colors: widget.colors,
          selectable: vm.selectionMode,
          selected: vm.isSelected(entry),
          onTap: vm.selectionMode
              ? () => vm.toggleSelected(entry)
              : () => Navigator.of(context).pushNamed(
                    AppConstants.kRouteEventItemDetail,
                    arguments: entry.item.id,
                  ),
          onLongPress: () {
            vm.enterSelection();
            vm.toggleSelected(entry);
          },
        );
      },
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

/// Source chips, shown only when photos came from more than one place.
///
/// A card import and a tethered shot land in the same grid, and telling them
/// apart is how an operator answers "did the photographer's last set arrive".
class _QueueSourceBar extends StatelessWidget {
  const _QueueSourceBar({required this.vm, required this.colors});

  final EventQueueViewModel vm;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final options = vm.sourceOptions;
    if (options.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: options.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (context, i) {
            final option = options[i];
            final selected = option.value == QueueFilter.allSources
                ? vm.sourceFilter == null
                : vm.sourceFilter == option.value;
            return ChoiceChip(
              label: Text('${option.label} ${option.count}'),
              labelStyle: const TextStyle(fontSize: 11),
              selected: selected,
              onSelected: (_) => vm.setSourceFilter(option.value),
            );
          },
        ),
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({
    required this.entry,
    required this.colors,
    this.selectable = false,
    this.selected = false,
    this.onTap,
    this.onLongPress,
  });

  final QueueEntry entry;
  final AppColors colors;
  final bool selectable;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final file = entry.thumbnailFile;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  file == null
                      ? Container(
                          color: colors.cardBackgroundColor,
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            color: colors.secondaryTextColor,
                          ),
                        )
                      // The dedicated ~320px thumbnail, decoded small again for the
                      // tile. Never the print derivative: decoding dozens of 2880px
                      // JPEGs is the heap mistake the old import tray made.
                      : Image.file(
                          file,
                          fit: BoxFit.cover,
                          cacheWidth: 240,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => Container(
                            color: colors.cardBackgroundColor,
                          ),
                        ),
                  // Where this photo is in the print queue, so an operator
                  // waiting on one can see how far down it is.
                  if (entry.printPosition != null)
                    Align(
                      alignment: Alignment.topLeft,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '#${entry.printPosition}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (entry.isOnPrinter)
                    Align(
                      alignment: Alignment.topLeft,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.print,
                          size: 16,
                          color: colors.successColor,
                        ),
                      ),
                    ),
                  if (selectable)
                    Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          selected
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          size: 20,
                          color: selected
                              ? colors.successColor
                              : colors.secondaryTextColor,
                        ),
                      ),
                    ),
                ],
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
      ),
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
