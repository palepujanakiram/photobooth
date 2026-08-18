import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/event_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../views/widgets/app_scaffold.dart';
import '../../views/widgets/cached_network_image.dart';
import '../../views/widgets/theme_card.dart';
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
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    vm.queue.isEmpty
                        ? AppStrings.eventStationWaitingTheme
                        : '${vm.queue.length} waiting',
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
                  const Spacer(),
                  ElevatedButton(
                    onPressed: vm.queue.isEmpty || vm.isBusy
                        ? null
                        : () => vm.claimNext(),
                    child: vm.isBusy
                        ? const CircularProgressIndicator()
                        : const Text('Style next guest'),
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
        if (preview.isNotEmpty)
          SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(16),
              itemCount: preview.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) => AspectRatio(
                aspectRatio: 2 / 3,
                child: CachedNetworkImage(imageUrl: preview[i]),
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
