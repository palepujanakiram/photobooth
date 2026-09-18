import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/app_strings.dart';
import '../../views/widgets/app_scaffold.dart';
import '../event_station/event_station_chrome_view_widgets.dart';
import 'event_device_capture_view_widgets.dart';
import 'event_device_capture_viewmodel.dart';

/// Phone / webcam capture for the event hub.
class EventDeviceCaptureScreen extends StatelessWidget {
  const EventDeviceCaptureScreen({super.key, this.viewModel});

  final EventDeviceCaptureViewModel? viewModel;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<EventDeviceCaptureViewModel>(
      create: (_) => viewModel ?? EventDeviceCaptureViewModel(),
      child: const EventStationBoundShell(child: _DeviceCaptureBody()),
    );
  }
}

class _DeviceCaptureBody extends StatelessWidget {
  const _DeviceCaptureBody();

  @override
  Widget build(BuildContext context) {
    return Consumer<EventDeviceCaptureViewModel>(
      builder: (context, vm, _) {
        return AppScaffold(
          title: AppStrings.eventHubCapture,
          showBackButton: true,
          onBackPressed: () => Navigator.of(context).pop(vm.queuedCount),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: EventDeviceCapturePreview(shot: vm.pending)),
                if (vm.message != null && vm.message!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(vm.message!, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 12),
                EventDeviceCaptureActions(
                  hasPending: vm.hasPending,
                  busy: vm.isBusy,
                  onShutter: () => unawaited(vm.shutter()),
                  onAccept: () => unawaited(vm.accept()),
                  onRetake: vm.retake,
                  onDone: () => Navigator.of(context).pop(vm.queuedCount),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
