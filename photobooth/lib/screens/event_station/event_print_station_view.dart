import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/event_station_models.dart';
import '../../services/app_settings_manager.dart';
import '../../services/event_manager.dart';
import '../../services/print_service.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../views/widgets/app_scaffold.dart';
import 'event_print_station_viewmodel.dart';
import 'event_station_view_widgets.dart';

class EventPrintStationScreen extends StatelessWidget {
  const EventPrintStationScreen({super.key});

  Future<void> _changeRole(BuildContext context) async {
    await EventManager().setStationRole(null);
    if (!context.mounted) return;
    await Navigator.of(context)
        .pushReplacementNamed(AppConstants.kRouteEventStation);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => EventPrintStationViewModel(
        printFn: (file, {required printSize}) async {
          final settings = AppSettingsManager();
          try {
            await settings.fetchSettings();
          } catch (_) {}
          await PrintService().printImageSilent(
            file,
            printSize: printSize,
            settings: settings.settings,
          );
        },
      )..startPolling(),
      child: AppScaffold(
        title: AppStrings.eventStationPrint,
        showBackButton: true,
        onBackPressed: () => _changeRole(context),
        actions: [
          TextButton(
            onPressed: () => _changeRole(context),
            child: const Text(AppStrings.eventStationChangeRole),
          ),
        ],
        child: Consumer<EventPrintStationViewModel>(
          builder: (context, vm, _) {
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
                            child: Text(AppStrings.eventStationEmptyPrint),
                          )
                        : GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.68,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                            itemCount: vm.filteredJobs.length,
                            itemBuilder: (context, i) {
                              final job = vm.filteredJobs[i];
                              return EventStationPhotoTile(
                                imageUrl: job.imageUrl,
                                status: job.status,
                                footer: _PrintTileActions(viewModel: vm, job: job),
                              );
                            },
                          ),
                  ),
                  ElevatedButton(
                    onPressed: vm.queue.isEmpty || vm.isBusy
                        ? null
                        : () => vm.printNext(),
                    child: vm.isBusy
                        ? const CircularProgressIndicator()
                        : const Text(AppStrings.eventStationPrintNow),
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

class _PrintTileActions extends StatelessWidget {
  const _PrintTileActions({required this.viewModel, required this.job});

  final EventPrintStationViewModel viewModel;
  final EventPrintStationJob job;

  @override
  Widget build(BuildContext context) {
    if (job.canReissue) {
      return TextButton(
        onPressed: viewModel.isBusy ? null : () => viewModel.reissueJob(job),
        child: const Text(AppStrings.eventStationReprint),
      );
    }
    if (job.status == 'PENDING') {
      return TextButton(
        onPressed: viewModel.isBusy ? null : () => viewModel.printJob(job),
        child: const Text(AppStrings.eventStationPrintNow),
      );
    }
    return const SizedBox.shrink();
  }
}
