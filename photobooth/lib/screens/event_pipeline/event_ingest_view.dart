import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/event_manager.dart';
import '../../services/event_pipeline/ingest/ingest_worker.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_scaffold.dart';
import '../event_station/event_station_chrome_view_widgets.dart';
import 'event_ingest_view_widgets.dart';
import 'event_pipeline_status_strip.dart';
import 'event_ingest_viewmodel.dart';

/// SD import station: detect a card, scan, select, import.
///
/// A fourth station role rather than a control inside Capture. The two screens
/// have opposite designs — Capture is fire-and-forget with no local queue and
/// navigates away to `/capture` between guests, while an import is stateful and
/// has to survive minutes on screen.
class EventIngestScreen extends StatelessWidget {
  const EventIngestScreen({super.key, this.viewModel});

  final EventIngestViewModel? viewModel;

  Future<void> _changeRole(BuildContext context) async {
    await EventManager().setStationRole(null);
    if (!context.mounted) return;
    await Navigator.of(context)
        .pushReplacementNamed(AppConstants.kRouteEventStation);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<EventIngestViewModel>(
      create: (_) => (viewModel ?? EventIngestViewModel())..start(),
      child: AppScaffold(
        title: AppStrings.eventStationSdImport,
        showBackButton: true,
        onBackPressed: () => _changeRole(context),
        actions: [
          TextButton(
            onPressed: () => _changeRole(context),
            child: const Text(AppStrings.eventStationChangeRole),
          ),
        ],
        child: EventStationBoundShell(
          child: Consumer<EventIngestViewModel>(
            builder: (context, vm, _) => _IngestBody(vm: vm),
          ),
        ),
      ),
    );
  }
}

/// Split out so the phase switch stays small — the whole screen in one build
/// method would blow the cognitive-complexity limit.
class _IngestBody extends StatelessWidget {
  const _IngestBody({required this.vm});

  final EventIngestViewModel vm;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: switch (vm.phase) {
        IngestPhase.noCard => _noCard(colors),
        IngestPhase.needsPermission => _needsPermission(colors),
        IngestPhase.unreadable => _unreadable(colors),
        IngestPhase.scanning =>
          IngestScanningPanel(appColors: colors, count: vm.scanningCount),
        IngestPhase.importing => IngestProgressPanel(
            appColors: colors,
            progress: vm.progress ??
                const IngestProgress(
                  done: 0,
                  total: 0,
                  imported: 0,
                  duplicates: 0,
                  failed: 0,
                ),
          ),
        IngestPhase.complete => _complete(colors),
        IngestPhase.review => _review(colors),
      },
    );
  }

  Widget _noCard(AppColors colors) {
    return IngestMessagePanel(
      appColors: colors,
      icon: Icons.sd_card_outlined,
      title: 'Insert a card',
      detail: vm.errorMessage ??
          'Put the photographer\'s card in the reader. '
              'It will be scanned automatically.',
      actionLabel: vm.isBusy ? null : 'Scan card',
      onAction: vm.refresh,
    );
  }

  Widget _needsPermission(AppColors colors) {
    return IngestMessagePanel(
      appColors: colors,
      icon: Icons.lock_outline,
      title: 'Photo access needed',
      detail: 'Cards are read through the system media library, '
          'so this device needs photo access once.',
      actionLabel: 'Grant access',
      onAction: vm.refresh,
    );
  }

  Widget _unreadable(AppColors colors) {
    return IngestMessagePanel(
      appColors: colors,
      icon: Icons.error_outline,
      tone: colors.warningColor,
      // Distinct from "no card": the volume mounted but was never indexed, so
      // reporting it as empty would be a lie.
      title: 'Card not readable',
      detail: 'The card mounted but the system has not indexed it. '
          'Reseat it, or try a different card.',
      actionLabel: 'Try again',
      onAction: vm.refresh,
    );
  }

  Widget _complete(AppColors colors) {
    final report = vm.report;
    final detail = report == null
        ? ''
        : '${report.imported} imported'
            '${report.duplicates > 0 ? ' · ${report.duplicates} already had' : ''}'
            '${report.failed > 0 ? ' · ${report.failed} failed' : ''}';
    return IngestMessagePanel(
      appColors: colors,
      icon: Icons.check_circle_outline,
      tone: colors.successColor,
      title: 'Safe to remove card',
      detail: detail,
      actionLabel: 'Done',
      onAction: vm.done,
    );
  }

  Widget _review(AppColors colors) {
    final scan = vm.scan;
    final settings = vm.settings;
    if (scan == null || settings == null) return const SizedBox.shrink();

    if (!scan.hasNew) {
      return IngestMessagePanel(
        appColors: colors,
        icon: Icons.done_all,
        title: scan.isRawOnly ? 'Only RAW files found' : 'Nothing new',
        detail: scan.isRawOnly
            ? '${scan.skippedRaw} RAW files are on this card. '
                'Only JPEG, HEIC and PNG can be imported.'
            : 'All ${scan.alreadyImported} photos on this card '
                'have already been imported.',
        actionLabel: 'Scan again',
        onAction: vm.refresh,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const EventPipelineStatusStrip(),
        IngestSummaryBar(appColors: colors, result: scan),
        const SizedBox(height: 8),
        IngestFolderList(
          appColors: colors,
          folders: scan.folders,
          isIncluded: vm.isFolderIncluded,
          onToggle: vm.toggleFolder,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: IngestCandidateGrid(
            appColors: colors,
            candidates: vm.candidates,
            isSelected: vm.isSelected,
            onToggle: vm.toggleItem,
          ),
        ),
        const SizedBox(height: 8),
        IngestActionBar(
          appColors: colors,
          steps: vm.resolvedSteps,
          copies: settings.defaultCopies,
          printSize: settings.printSize,
          selectedCount: vm.selectedCount,
          enabled: !vm.isBusy,
          onSelectAll: vm.selectAll,
          onSelectNone: vm.selectNone,
          onImport: vm.importSelected,
        ),
      ],
    );
  }
}
