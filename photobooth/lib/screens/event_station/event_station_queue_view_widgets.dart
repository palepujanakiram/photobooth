import 'package:flutter/material.dart';

import '../../services/image_cache_source.dart';
import '../../utils/app_strings.dart';
import '../../utils/event_station_timing.dart';
import '../../views/widgets/cached_network_image.dart';

class EventStationThumb extends StatelessWidget {
  const EventStationThumb({
    super.key,
    required this.imageUrl,
    required this.cacheId,
    this.size = 96,
    this.status,
  });

  final String imageUrl;
  final String cacheId;
  final double size;
  final String? status;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            imageUrl.isEmpty
                ? const ColoredBox(color: Color(0x14000000))
                : CachedNetworkImage(
                    imageUrl: imageUrl,
                    cacheKey: eventStationThumbCacheKey(cacheId),
                    fit: BoxFit.cover,
                  ),
            if (status != null && status!.isNotEmpty)
              Align(
                alignment: Alignment.bottomCenter,
                child: ColoredBox(
                  color: const Color(0x99000000),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      status!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class EventStationStripGrid extends StatelessWidget {
  const EventStationStripGrid({
    super.key,
    required this.itemCount,
    required this.thumbBuilder,
    this.emptyLabel = AppStrings.eventStationEmptyCaptures,
  });

  final int itemCount;
  final IndexedWidgetBuilder thumbBuilder;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (itemCount <= 0) {
      return Center(child: Text(emptyLabel));
    }
    return GridView.builder(
      itemCount: itemCount,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 108,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1,
      ),
      itemBuilder: thumbBuilder,
    );
  }
}

class EventStationQueueRow extends StatelessWidget {
  const EventStationQueueRow({
    super.key,
    required this.imageUrl,
    required this.cacheId,
    required this.statusLabel,
    required this.timingLabel,
    this.failed = false,
    this.actions = const [],
    this.onTap,
  });

  final String imageUrl;
  final String cacheId;
  final String statusLabel;
  final String timingLabel;
  final bool failed;
  final List<Widget> actions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                EventStationThumb(
                  imageUrl: imageUrl,
                  cacheId: cacheId,
                  size: 72,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: failed ? scheme.error : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        timingLabel,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String eventStationRowTiming(EventStationJobTimes times, {DateTime? now}) {
  return eventStationQueueSummary(times, now: now);
}
