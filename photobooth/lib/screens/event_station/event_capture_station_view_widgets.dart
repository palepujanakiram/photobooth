import 'package:flutter/material.dart';

import '../../utils/app_strings.dart';
import '../../utils/event_bulk_import.dart';
import 'event_capture_station_viewmodel.dart';

class EventCaptureImportTray extends StatelessWidget {
  const EventCaptureImportTray({super.key, required this.viewModel});

  final EventCaptureStationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppStrings.eventStationImportTrayTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          AppStrings.eventStationImportHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: GridView.builder(
            itemCount: viewModel.importItems.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 140,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1,
            ),
            itemBuilder: (context, index) {
              final item = viewModel.importItems[index];
              return _ImportThumb(
                item: item,
                onTap: viewModel.isBusy
                    ? null
                    : () => viewModel.toggleImportSelection(item.id),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton(
              onPressed: viewModel.isBusy
                  ? null
                  : () => viewModel.importSelectedAsGuests(),
              child: const Text(AppStrings.eventStationImportAssign),
            ),
            OutlinedButton(
              onPressed:
                  viewModel.isBusy ? null : viewModel.discardSelectedImport,
              child: const Text(AppStrings.eventStationImportDiscard),
            ),
            TextButton(
              onPressed: viewModel.isBusy ? null : viewModel.clearImportTray,
              child: const Text(AppStrings.eventStationImportClearTray),
            ),
          ],
        ),
      ],
    );
  }
}

class EventCaptureStationActions extends StatelessWidget {
  const EventCaptureStationActions({
    super.key,
    required this.viewModel,
    required this.onCaptureNext,
  });

  final EventCaptureStationViewModel viewModel;
  final VoidCallback onCaptureNext;

  @override
  Widget build(BuildContext context) {
    final progress = viewModel.importProgress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (progress != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _progressLabel(progress),
              textAlign: TextAlign.center,
            ),
          ),
        OutlinedButton(
          onPressed: viewModel.isBusy ? null : viewModel.pickFromCard,
          child: const Text(AppStrings.eventStationImportFromCard),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: viewModel.isBusy ? null : onCaptureNext,
          child: viewModel.isBusy && progress == null
              ? const CircularProgressIndicator()
              : const Text(AppStrings.eventStationNextGuest),
        ),
      ],
    );
  }

  String _progressLabel(EventBulkImportProgress progress) {
    final phase = progress.phase == EventBulkImportPhase.reading
        ? AppStrings.eventStationImportReading
        : AppStrings.eventStationImportUploading;
    return '$phase ${progress.done}/${progress.total}';
  }
}

class _ImportThumb extends StatelessWidget {
  const _ImportThumb({required this.item, required this.onTap});

  final EventBulkImportItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(item.bytes, fit: BoxFit.cover, gaplessPlayback: true),
            if (item.selected)
              ColoredBox(
                color: scheme.primary.withValues(alpha: 0.35),
                child: Icon(Icons.check_circle, color: scheme.onPrimary),
              ),
          ],
        ),
      ),
    );
  }
}
