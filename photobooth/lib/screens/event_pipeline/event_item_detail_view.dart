import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_scaffold.dart';
import 'event_item_detail_view_widgets.dart';
import 'event_item_detail_viewmodel.dart';

/// One photograph: every version of it, why it stalled, and what to do next.
///
/// Reached by tapping any tile in the queue.
class EventItemDetailScreen extends StatelessWidget {
  const EventItemDetailScreen({super.key, required this.mediaId, this.viewModel});

  final String mediaId;
  final EventItemDetailViewModel? viewModel;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<EventItemDetailViewModel>(
      create: (_) =>
          (viewModel ?? EventItemDetailViewModel(mediaId: mediaId))..start(),
      child: Consumer<EventItemDetailViewModel>(
        builder: (context, vm, _) => AppScaffold(
          title: vm.title,
          showBackButton: true,
          child: _DetailBody(vm: vm),
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.vm});

  final EventItemDetailViewModel vm;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (vm.isRemoved) {
      return _message(colors, 'This photo has been removed.');
    }
    if (vm.item == null) {
      return _message(colors, vm.errorMessage ?? 'Loading…');
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ItemRenditionStrip(appColors: colors, renditions: vm.renditions),
          const SizedBox(height: 16),
          ItemFactsTable(appColors: colors, vm: vm),
          const SizedBox(height: 12),
          ItemTimingTable(appColors: colors, timings: vm.timings),
          const SizedBox(height: 16),
          ItemDetailActions(
            appColors: colors,
            vm: vm,
            onRemoved: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _message(AppColors colors, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.secondaryTextColor),
        ),
      ),
    );
  }
}
