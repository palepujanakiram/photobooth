import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_settings_manager.dart';
import '../../services/event_manager.dart';
import '../../services/print_service.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../views/widgets/app_scaffold.dart';
import '../../views/widgets/cached_network_image.dart';
import 'event_print_station_viewmodel.dart';

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
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    vm.queue.isEmpty
                        ? AppStrings.eventStationWaitingPrint
                        : '${vm.queue.length} ready to print',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20),
                  ),
                  if (vm.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        vm.errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  if (vm.queue.isNotEmpty)
                    Expanded(
                      child: ListView.separated(
                        itemCount: vm.queue.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final job = vm.queue[i];
                          return SizedBox(
                            height: 160,
                            child: CachedNetworkImage(imageUrl: job.imageUrl),
                          );
                        },
                      ),
                    )
                  else
                    const Spacer(),
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
