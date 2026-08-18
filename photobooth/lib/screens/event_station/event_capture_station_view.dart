import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/event_station_models.dart';
import '../../services/event_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../views/widgets/app_scaffold.dart';
import '../../views/widgets/app_snackbar.dart';
import '../../views/widgets/cached_network_image.dart';
import 'event_capture_station_viewmodel.dart';
import 'event_station_view_widgets.dart';

class EventCaptureStationScreen extends StatelessWidget {
  const EventCaptureStationScreen({super.key});

  Future<void> _changeRole(BuildContext context) async {
    await EventManager().setStationRole(null);
    if (!context.mounted) return;
    await Navigator.of(context)
        .pushReplacementNamed(AppConstants.kRouteEventStation);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => EventCaptureStationViewModel()..startPolling(),
      child: AppScaffold(
        title: AppStrings.eventStationCapture,
        showBackButton: true,
        onBackPressed: () => _changeRole(context),
        actions: [
          TextButton(
            onPressed: () => _changeRole(context),
            child: const Text(AppStrings.eventStationChangeRole),
          ),
        ],
        child: Consumer<EventCaptureStationViewModel>(
          builder: (context, vm, _) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EventStationStatsBar(stats: vm.stats),
                  const SizedBox(height: 12),
                  EventStationImageCarousel(urls: vm.carouselUrls),
                  const SizedBox(height: 12),
                  EventStationStatusTabs(
                    selected: vm.statusFilter,
                    onSelected: vm.setStatusFilter,
                    pendingCount: stationStatusCount(
                      vm.captures,
                      'PENDING',
                      (e) => e.status,
                    ),
                    claimedCount: stationStatusCount(
                      vm.captures,
                      'CLAIMED',
                      (e) => e.status,
                    ),
                    doneCount: stationStatusCount(
                      vm.captures,
                      'DONE',
                      (e) => e.status,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: vm.filteredCaptures.isEmpty
                        ? const Center(
                            child: Text(AppStrings.eventStationEmptyCaptures),
                          )
                        : ListView.separated(
                            itemCount: vm.filteredCaptures.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final item = vm.filteredCaptures[i];
                              final thumb = item.previewUrls.isEmpty
                                  ? null
                                  : item.previewUrls.first;
                              return ListTile(
                                leading: thumb == null
                                    ? null
                                    : SizedBox(
                                        width: 56,
                                        height: 56,
                                        child: CachedNetworkImage(
                                          imageUrl: thumb,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                title: Text(item.status),
                                subtitle: Text(item.sessionId),
                              );
                            },
                          ),
                  ),
                  if (vm.hasError)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        vm.errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  ElevatedButton(
                    onPressed: vm.isBusy
                        ? null
                        : () async {
                            final ok = await vm.startNextGuest();
                            if (!context.mounted) return;
                            if (!ok) {
                              AppSnackBar.showError(
                                context,
                                vm.errorMessage ?? AppConstants.kErrorUnknown,
                              );
                              return;
                            }
                            await Navigator.of(context).pushReplacementNamed(
                              AppConstants.kRouteCapture,
                            );
                          },
                    child: vm.isBusy
                        ? const CircularProgressIndicator()
                        : const Text(AppStrings.eventStationNextGuest),
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
