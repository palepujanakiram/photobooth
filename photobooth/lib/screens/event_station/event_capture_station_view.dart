import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/event_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../views/widgets/app_scaffold.dart';
import '../../views/widgets/app_snackbar.dart';
import 'event_capture_station_viewmodel.dart';

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
      create: (_) => EventCaptureStationViewModel(),
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
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    AppStrings.eventStationCaptureHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18),
                  ),
                  const Spacer(),
                  if (vm.hasError)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
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
