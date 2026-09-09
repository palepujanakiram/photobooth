import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/event_pipeline/event_readiness.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_scaffold.dart';
import '../event_station/event_station_chrome_view_widgets.dart';
import 'event_hub_view_widgets.dart';
import 'event_hub_viewmodel.dart';

/// The event pipeline's entry point, and the screen an operator leaves open.
///
/// Replaces the station picker when the flag is on. Three ingestion sources now
/// feed one local queue on one device, so "which role is this device" stops
/// being the question — what an operator needs to know is whether everything is
/// ready, what is in the queue, and what is stuck (spec §1).
class EventHubScreen extends StatelessWidget {
  const EventHubScreen({super.key, this.viewModel});

  final EventHubViewModel? viewModel;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<EventHubViewModel>(
      create: (_) => (viewModel ?? EventHubViewModel())..start(),
      // The hub is the event's root: splash reaches it with a replacement, so
      // there is nothing beneath it and a back tap would drop the operator out
      // of the app mid-event. Leaving an event is a deliberate action, not a
      // stray tap — see the settings screen.
      child: PopScope(
        canPop: false,
        child: AppScaffold(
          title: AppStrings.eventHubTitle,
          showBackButton: false,
          actions: [
            // The gear from the spec's header: event settings are reached from
            // the event, not from Kiosk settings.
            IconButton(
              tooltip: 'Event settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context)
                  .pushNamed(AppConstants.kRouteEventSettings),
            ),
          ],
          child: EventStationBoundShell(
            child: Consumer<EventHubViewModel>(
              builder: (context, vm, _) => _HubBody(vm: vm),
            ),
          ),
        ),
      ),
    );
  }
}

class _HubBody extends StatelessWidget {
  const _HubBody({required this.vm});

  final EventHubViewModel vm;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EventHubHeader(
            appColors: colors,
            name: vm.eventName,
            tagline: vm.eventTagline,
          ),
          EventHubReadinessBlock(
            appColors: colors,
            headline: vm.isSyncing ? AppStrings.eventHubSyncing : vm.headline,
            rows: vm.readinessRows,
            onExplain: (row) => _explain(context, row),
          ),
          const SizedBox(height: 12),
          EventHubCounterRow(
            appColors: colors,
            stats: vm.counters,
            onOpenFiltered: (stage) => _openQueue(context, stage),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: EventHubAction(
                  appColors: colors,
                  label: AppStrings.eventHubImport,
                  enabled: vm.canImport,
                  disabledReason: vm.importBlockedReason,
                  onPressed: () => Navigator.pushNamed(
                    context,
                    AppConstants.kRouteEventIngestStation,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: EventHubAction(
                  appColors: colors,
                  label: AppStrings.eventHubCapture,
                  enabled: vm.canCapture,
                  disabledReason: vm.captureBlockedReason,
                  onPressed: () => Navigator.pushNamed(
                    context,
                    AppConstants.kRouteEventCapture,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          EventHubAction(
            appColors: colors,
            label: AppStrings.eventHubOpenQueue,
            enabled: true,
            onPressed: () => _openQueue(context, null),
          ),
        ],
      ),
    );
  }

  void _openQueue(BuildContext context, String? stage) {
    Navigator.pushNamed(
      context,
      AppConstants.kRouteEventQueue,
      arguments: stage,
    );
  }

  /// The tappable explanation on an amber or red row.
  ///
  /// "Frames not cached" is the one that most needs this: it is silent until an
  /// event goes offline, and then every single item defers.
  void _explain(BuildContext context, ReadinessRow row) {
    final isSyncRow = row.kind == ReadinessKind.sync;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(row.label),
        content: Text(row.explanation ?? row.detail),
        actions: [
          if (isSyncRow)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                vm.resync();
              },
              child: const Text('Sync now'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
