import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/event_station_models.dart';
import '../../services/event_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../utils/event_bulk_import.dart';
import '../../views/widgets/app_scaffold.dart';
import '../event_pipeline/event_pipeline_status_strip.dart';
import '../../views/widgets/app_snackbar.dart';
import 'event_capture_station_view_widgets.dart';
import 'event_capture_station_viewmodel.dart';
import 'event_station_chrome_view_widgets.dart';
import 'event_station_view_widgets.dart';

Future<List<XFile>> pickEventCaptureImportImages() {
  return ImagePicker().pickMultiImage(
    maxWidth: AppConstants.kMaxImageWidth.toDouble(),
    maxHeight: AppConstants.kMaxImageHeight.toDouble(),
    imageQuality: AppConstants.kGalleryPickerImageQuality,
  );
}

class EventCaptureStationScreen extends StatelessWidget {
  const EventCaptureStationScreen({super.key});

  Future<void> _changeRole(BuildContext context) async {
    await EventManager().setStationRole(null);
    if (!context.mounted) return;
    await Navigator.of(context)
        .pushReplacementNamed(AppConstants.kRouteEventStation);
  }

  Future<void> _captureNext(
    BuildContext context,
    EventCaptureStationViewModel vm,
  ) async {
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
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => EventCaptureStationViewModel(
        importHooks: const EventCaptureImportHooks(
          pickImages: pickEventCaptureImportImages,
        ),
      )..startPolling(),
      child: AppScaffold(
        title: AppStrings.eventStationCapture,
        showBackButton: true,
        onBackPressed: () => _changeRole(context),
        actions: [
          EventStationChangeRoleButton(
            onPressed: () => _changeRole(context),
          ),
        ],
        child: EventStationBoundShell(
          child: Consumer<EventCaptureStationViewModel>(
          builder: (context, vm, _) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Local pipeline counts. Renders nothing when the ledger is
                  // empty, so a server-brokered station is unchanged.
                  const EventPipelineStatusStrip(),
                  EventStationStatsBar(stats: vm.stats, delivery: vm.delivery),
                  const SizedBox(height: 12),
                  EventStationStatusTabs(
                    selected: vm.statusFilter,
                    onSelected: vm.setStatusFilter,
                    includeAll: true,
                    allCount: vm.captures.length,
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
                  Expanded(child: EventCaptureStationPane(viewModel: vm)),
                  if (vm.hasError)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        vm.errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  EventCaptureStationActions(
                    viewModel: vm,
                    onCaptureNext: () => _captureNext(context, vm),
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
