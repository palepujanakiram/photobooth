import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/event_pipeline/event_pipeline_config.dart';
import '../../services/event_pipeline/event_pipeline_stats.dart';
import '../../views/widgets/app_colors.dart';

/// Pipeline counts, shown on every station.
///
/// The event box reads the local replica so the strip still moves offline.
/// Runtimes without SQLite (web) fall back to the shared ZenAI ledger.
///
/// Renders nothing when the pipeline holds no items, so a station running the
/// server-brokered flow is visually unchanged.
class EventPipelineStatusStrip extends StatefulWidget {
  const EventPipelineStatusStrip({
    super.key,
    this.reader,
    this.enabled,
    this.refreshInterval = const Duration(seconds: 5),
  });

  final EventPipelineStatsReader? reader;

  /// Overrides the resolved pipeline flag. Tests pass this; production reads it.
  final bool? enabled;

  final Duration refreshInterval;

  @override
  State<EventPipelineStatusStrip> createState() =>
      _EventPipelineStatusStripState();
}

class _EventPipelineStatusStripState extends State<EventPipelineStatusStrip> {
  late final EventPipelineStatsReader _reader =
      widget.reader ?? EventPipelineStatsReader();

  Timer? _timer;
  EventPipelineStats _stats = const EventPipelineStats();

  @override
  void initState() {
    super.initState();
    unawaited(_begin());
  }

  /// Does nothing at all when the pipeline is off.
  ///
  /// Without this a purely server-brokered event station would open the pipeline
  /// database and poll it every few seconds for counts that are always zero.
  Future<void> _begin() async {
    final enabled = widget.enabled ??
        (await EventPipelineConfig().resolve()).pipelineEnabled;
    if (!mounted || !enabled) return;
    await _load();
    if (!mounted) return;
    _timer = Timer.periodic(widget.refreshInterval, (_) => unawaited(_load()));
  }

  Future<void> _load() async {
    final stats = await _reader.read();
    if (!mounted) return;
    setState(() => _stats = stats);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_stats.isEmpty) return const SizedBox.shrink();
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.cardBackgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _stats.printPaused ? colors.warningColor : colors.dividerColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _stats.summary,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textColor,
            ),
          ),
          if (_stats.printPaused)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.pause_circle_outline,
                    size: 14,
                    color: colors.warningColor,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      // Named rather than implied: a paused queue looks like a
                      // stalled one, and the operator needs to know it is
                      // waiting on them, not broken.
                      'Print queue paused — check ribbon, paper and cover.',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.warningColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
