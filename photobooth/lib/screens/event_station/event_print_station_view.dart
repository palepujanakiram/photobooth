import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/event_station_models.dart';
import '../../services/app_settings_manager.dart';
import '../../services/event_manager.dart';
import '../../services/print_service.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../utils/event_station_timing.dart';
import '../../views/widgets/app_scaffold.dart';
import '../../views/widgets/generated_image_preview_screen.dart';
import 'event_print_station_viewmodel.dart';
import 'event_station_chrome_view_widgets.dart';
import 'event_station_queue_view_widgets.dart';
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
            trySelphy: false,
            prepareForDnp: false,
          );
        },
      )..startPolling(),
      child: AppScaffold(
        title: AppStrings.eventStationPrint,
        showBackButton: true,
        onBackPressed: () => _changeRole(context),
        actions: [
          EventStationChangeRoleButton(
            onPressed: () => _changeRole(context),
          ),
        ],
        child: EventStationBoundShell(
          child: Consumer<EventPrintStationViewModel>(
          builder: (context, vm, _) {
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
                            child: Text(AppStrings.eventStationEmptyPrint),
                          )
                        : ListView.builder(
                            itemCount: vm.filteredJobs.length,
                            itemBuilder: (context, i) {
                              final job = vm.filteredJobs[i];
                              return EventPrintQueueTile(
                                job: job,
                                busy: vm.isBusy,
                                onPrint: job.status == 'PENDING'
                                    ? () => vm.printJob(job)
                                    : null,
                                onReprint: job.canReissue
                                    ? () => vm.reissueJob(job)
                                    : null,
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
      ),
    );
  }
}

class EventPrintQueueTile extends StatelessWidget {
  const EventPrintQueueTile({
    super.key,
    required this.job,
    required this.busy,
    this.onPrint,
    this.onReprint,
  });

  final EventPrintStationJob job;
  final bool busy;
  final VoidCallback? onPrint;
  final VoidCallback? onReprint;

  @override
  Widget build(BuildContext context) {
    final previewUrl = job.imageUrl.trim();
    final row = EventStationQueueRow(
      imageUrl: job.imageUrl,
      cacheId: job.id,
      statusLabel: eventStationDisplayStatus(job.status, job.times),
      timingLabel: eventStationRowTiming(job.times),
      failed: job.times.isFailed,
      onTap: previewUrl.isEmpty
          ? null
          : () {
              unawaited(
                showGeneratedImagePreview(
                  context,
                  imageUrl: previewUrl,
                  title: AppStrings.eventStationPrintPreview,
                  subtitle: AppStrings.eventStationPrintPreviewHint,
                ),
              );
            },
      actions: [
        if (onPrint != null)
          TextButton(
            onPressed: busy ? null : onPrint,
            child: const Text(AppStrings.eventStationPrintNow),
          ),
        if (onReprint != null)
          TextButton(
            onPressed: busy ? null : onReprint,
            child: const Text(AppStrings.eventStationReprint),
          ),
      ],
    );
    if (previewUrl.isEmpty) return row;
    return Tooltip(
      message: AppStrings.eventStationPrintPreview,
      child: row,
    );
  }
}
