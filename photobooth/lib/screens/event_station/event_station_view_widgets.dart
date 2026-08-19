import 'package:flutter/material.dart';

import '../../models/event_station_models.dart';
import '../../utils/app_strings.dart';
import '../../views/widgets/cached_network_image.dart';

class EventStationStatsBar extends StatelessWidget {
  const EventStationStatsBar({super.key, required this.stats});

  final EventStationStats stats;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          children: [
            Row(
              children: [
                _StatCell(
                  label: AppStrings.eventStationStatsCaptures,
                  value: '${stats.captures}',
                ),
                _StatCell(
                  label: AppStrings.eventStationStatsTheme,
                  value:
                      '${stats.themePending} / ${stats.themeClaimed} / ${stats.themeDone}',
                ),
                _StatCell(
                  label: AppStrings.eventStationStatsPrint,
                  value:
                      '${stats.printPending} / ${stats.printClaimed} / ${stats.printDone}',
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              AppStrings.eventStationStatsLegend,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class EventStationStatusTabs extends StatelessWidget {
  const EventStationStatusTabs({
    super.key,
    required this.selected,
    required this.onSelected,
    this.pendingCount,
    this.claimedCount,
    this.doneCount,
  });

  final String selected;
  final ValueChanged<String> onSelected;
  final int? pendingCount;
  final int? claimedCount;
  final int? doneCount;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: [
        ButtonSegment(
          value: 'PENDING',
          label: Text(_tab(AppStrings.eventStationStatusPending, pendingCount)),
        ),
        ButtonSegment(
          value: 'CLAIMED',
          label: Text(_tab(AppStrings.eventStationStatusClaimed, claimedCount)),
        ),
        ButtonSegment(
          value: 'DONE',
          label: Text(_tab(AppStrings.eventStationStatusDone, doneCount)),
        ),
      ],
      selected: {selected},
      onSelectionChanged: (next) {
        if (next.isEmpty) return;
        onSelected(next.first);
      },
    );
  }

  String _tab(String label, int? count) {
    if (count == null) return label;
    return '$label $count';
  }
}

class EventStationImageCarousel extends StatefulWidget {
  const EventStationImageCarousel({super.key, required this.urls});

  final List<String> urls;

  @override
  State<EventStationImageCarousel> createState() =>
      _EventStationImageCarouselState();
}

class _EventStationImageCarouselState extends State<EventStationImageCarousel> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty) {
      return const SizedBox(
        height: 180,
        child: Center(child: Text(AppStrings.eventStationEmptyCaptures)),
      );
    }
    return Column(
      children: [
        SizedBox(
          height: 240,
          child: PageView.builder(
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: widget.urls[i],
                    fit: BoxFit.contain,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text('${_page + 1} / ${widget.urls.length}'),
      ],
    );
  }
}

class EventStationPhotoTile extends StatelessWidget {
  const EventStationPhotoTile({
    super.key,
    required this.imageUrl,
    required this.status,
    this.onTap,
    this.footer,
  });

  final String imageUrl;
  final String status;
  final VoidCallback? onTap;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: imageUrl.isEmpty
                  ? const ColoredBox(color: Colors.black12)
                  : CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                status,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (footer != null) footer!,
          ],
        ),
      ),
    );
  }
}
