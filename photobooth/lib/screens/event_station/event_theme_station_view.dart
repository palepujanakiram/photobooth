import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/event_info_model.dart';
import '../../models/event_station_models.dart';
import '../../services/event_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../utils/event_station_chrome.dart';
import '../../utils/event_station_timing.dart';
import '../../views/widgets/app_scaffold.dart';
import 'event_station_chrome_view_widgets.dart';
import 'event_station_queue_view_widgets.dart';
import 'event_station_view_widgets.dart';
import 'event_theme_station_viewmodel.dart';

class EventThemeStationScreen extends StatelessWidget {
  const EventThemeStationScreen({super.key});

  Future<void> _changeRole(BuildContext context) async {
    await EventManager().setStationRole(null);
    if (!context.mounted) return;
    await Navigator.of(context)
        .pushReplacementNamed(AppConstants.kRouteEventStation);
  }

  Future<void> _confirmDrop(
    BuildContext context,
    EventThemeStationViewModel vm,
    EventThemeStationJob job,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.eventStationDropConfirmTitle),
        content: const Text(AppStrings.eventStationDropConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(AppStrings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(AppStrings.eventStationDropOff),
          ),
        ],
      ),
    );
    if (ok == true) await vm.skipJob(job.id);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => EventThemeStationViewModel()..startPolling(),
      child: AppScaffold(
        title: AppStrings.eventStationTheme,
        showBackButton: true,
        onBackPressed: () => _changeRole(context),
        actions: [
          EventStationChangeRoleButton(
            onPressed: () => _changeRole(context),
          ),
        ],
        child: EventStationBoundShell(
          child: Consumer<EventThemeStationViewModel>(
          builder: (context, vm, _) {
            if (vm.hasClaimedJob) {
              return _ClaimedThemeBody(viewModel: vm);
            }
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EventStationStatsBar(stats: vm.stats, delivery: vm.delivery),
                  const SizedBox(height: 12),
                  EventStationStatusTabs(
                    selected: vm.statusFilter,
                    onSelected: vm.setStatusFilter,
                    includeAll: true,
                    allCount: vm.allJobs.length,
                    pendingCount: stationStatusCount(
                      vm.allJobs,
                      'PENDING',
                      (e) => e.status,
                    ),
                    claimedCount: stationStatusCount(
                      vm.allJobs,
                      'CLAIMED',
                      (e) => e.status,
                    ),
                    doneCount: stationStatusCount(
                      vm.allJobs,
                      'DONE',
                      (e) => e.status,
                    ),
                  ),
                  if (vm.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        vm.errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: vm.filteredJobs.isEmpty
                        ? const Center(
                            child: Text(AppStrings.eventStationEmptyTheme),
                          )
                        : ListView.builder(
                            itemCount: vm.filteredJobs.length,
                            itemBuilder: (context, i) {
                              final job = vm.filteredJobs[i];
                              return EventThemeQueueTile(
                                job: job,
                                busy: vm.isBusy,
                                onStyle: job.status == 'PENDING'
                                    ? () => vm.claimJob(job.id)
                                    : null,
                                onDrop: job.canSkip
                                    ? () => _confirmDrop(context, vm, job)
                                    : null,
                                onRetry: job.canRetry
                                    ? () => vm.retryJob(job.id)
                                    : null,
                              );
                            },
                          ),
                  ),
                  ElevatedButton(
                    onPressed: vm.queue.isEmpty || vm.isBusy
                        ? null
                        : () => vm.claimNext(),
                    child: vm.isBusy
                        ? const CircularProgressIndicator()
                        : const Text(AppStrings.eventStationStyleNext),
                  ),
                ],
              ),
            );
          },
        ),
        ),
      ),
    );
  }
}

class _ClaimedThemeBody extends StatelessWidget {
  const _ClaimedThemeBody({required this.viewModel});

  final EventThemeStationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final preview = viewModel.claimed?.previewUrls ?? const [];
    final skin =
        EventStationChromeScope.maybeOf(context)?.chrome.skin ??
            const EventSkinChrome();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: EventStationStatsBar(
            stats: viewModel.stats,
            delivery: viewModel.delivery,
          ),
        ),
        EventStationImageCarousel(urls: preview),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            AppStrings.eventStationPickLook,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Color(kEventLookSelectedBorder),
            ),
          ),
        ),
        if (viewModel.looks.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(AppStrings.eventStationNoThemes),
          )
        else
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.35,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: viewModel.looks.length,
              itemBuilder: (context, i) {
                final theme = viewModel.looks[i];
                return EventStationLookTile(
                  theme: theme,
                  skin: skin,
                  index: i,
                  selected: theme.id == viewModel.selectedThemeId,
                  onTap: () => viewModel.selectTheme(theme.id),
                );
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: viewModel.isBusy || viewModel.selectedThemeId == null
                ? null
                : () => viewModel.completeSelected(),
            child: const Text(AppStrings.eventStationAssignTheme),
          ),
        ),
      ],
    );
  }
}

class EventThemeQueueTile extends StatelessWidget {
  const EventThemeQueueTile({
    super.key,
    required this.job,
    required this.busy,
    this.onStyle,
    this.onDrop,
    this.onRetry,
  });

  final EventThemeStationJob job;
  final bool busy;
  final VoidCallback? onStyle;
  final VoidCallback? onDrop;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final url = job.previewUrls.isEmpty ? '' : job.previewUrls.first;
    return EventStationQueueRow(
      imageUrl: url,
      cacheId: job.sessionId,
      statusLabel: eventStationDisplayStatus(job.status, job.times),
      timingLabel: eventStationRowTiming(job.times),
      failed: job.times.isFailed,
      onTap: busy ? null : onStyle,
      actions: [
        if (onStyle != null)
          TextButton(
            onPressed: busy ? null : onStyle,
            child: const Text(AppStrings.eventStationStyleThis),
          ),
        if (onRetry != null)
          TextButton(
            onPressed: busy ? null : onRetry,
            child: const Text(AppStrings.eventStationReprocess),
          ),
        if (onDrop != null)
          TextButton(
            onPressed: busy ? null : onDrop,
            child: const Text(AppStrings.eventStationDropOff),
          ),
      ],
    );
  }
}
