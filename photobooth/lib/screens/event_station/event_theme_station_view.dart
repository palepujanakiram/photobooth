import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/event_station_models.dart';
import '../../services/event_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../views/widgets/app_scaffold.dart';
import '../../views/widgets/theme_card.dart';
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

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => EventThemeStationViewModel()..startPolling(),
      child: AppScaffold(
        title: AppStrings.eventStationTheme,
        showBackButton: true,
        onBackPressed: () => _changeRole(context),
        actions: [
          TextButton(
            onPressed: () => _changeRole(context),
            child: const Text(AppStrings.eventStationChangeRole),
          ),
        ],
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
                  EventStationStatsBar(stats: vm.stats),
                  const SizedBox(height: 12),
                  EventStationStatusTabs(
                    selected: vm.statusFilter,
                    onSelected: vm.setStatusFilter,
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
                        : GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 0.72,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                            itemCount: vm.filteredJobs.length,
                            itemBuilder: (context, i) {
                              final job = vm.filteredJobs[i];
                              final url = job.previewUrls.isEmpty
                                  ? ''
                                  : job.previewUrls.first;
                              return EventStationPhotoTile(
                                imageUrl: url,
                                status: job.status,
                                onTap: job.status == 'PENDING' && !vm.isBusy
                                    ? () => vm.claimJob(job.id)
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
    );
  }
}

class _ClaimedThemeBody extends StatelessWidget {
  const _ClaimedThemeBody({required this.viewModel});

  final EventThemeStationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final preview = viewModel.claimed?.previewUrls ?? const [];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: EventStationStatsBar(stats: viewModel.stats),
        ),
        EventStationImageCarousel(urls: preview),
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
                childAspectRatio: 0.7,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: viewModel.looks.length,
              itemBuilder: (context, i) {
                final theme = viewModel.looks[i];
                return ThemeCard(
                  theme: theme,
                  isSelected: theme.id == viewModel.selectedThemeId,
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
