import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/event_pipeline/ingest/ingest_diff.dart';
import '../../services/event_pipeline/ingest/ingest_worker.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_scaffold.dart';
import '../event_station/event_station_chrome_view_widgets.dart';
import 'event_ingest_view_widgets.dart';
import 'event_pipeline_status_strip.dart';
import 'event_ingest_viewmodel.dart';

/// Import from card: choose a volume, scan, select, import.
///
/// Reached from the hub, and returns to it. There is no station role to change
/// any more — three sources feed one queue on one device — so the header shows
/// which card is being read instead, which is the thing an operator with two
/// cards seated actually needs to know.
class EventIngestScreen extends StatelessWidget {
  const EventIngestScreen({super.key, this.viewModel});

  final EventIngestViewModel? viewModel;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<EventIngestViewModel>(
      create: (_) => (viewModel ?? EventIngestViewModel())..start(),
      child: Consumer<EventIngestViewModel>(
        builder: (context, vm, _) => AppScaffold(
          // Names the chosen card once there is one, so the title answers
          // "which card am I looking at" without a second glance.
          title: vm.volume?.displayLabel ?? AppStrings.eventHubImport,
          showBackButton: true,
          onBackPressed: () => _back(context, vm),
          actions: [
            // Imported photos have to be reachable, or they look lost the
            // moment the import finishes.
            IconButton(
              tooltip: AppStrings.eventQueueTitle,
              icon: const Icon(Icons.photo_library_outlined),
              onPressed: () => Navigator.of(context)
                  .pushNamed(AppConstants.kRouteEventQueue),
            ),
          ],
          child: EventStationBoundShell(child: _IngestBody(vm: vm)),
        ),
      ),
    );
  }

  /// Back steps out of a chosen card first, and only then off the screen.
  ///
  /// Otherwise an operator who tapped the wrong one of two seated cards has to
  /// leave to the hub and come back in to correct it.
  void _back(BuildContext context, EventIngestViewModel vm) {
    if (vm.volume != null && vm.phase != IngestPhase.importing) {
      unawaited(vm.backToVolumes());
      return;
    }
    Navigator.of(context).pop();
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
        IngestPhase.pickVolume => IngestVolumePicker(
            appColors: colors,
            volumes: vm.volumes,
            enabled: !vm.isBusy,
            onSelect: vm.selectVolume,
          ),
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
      title: 'Insert a card in the reader',
      detail: vm.errorMessage ??
          'Cards appear here as they are seated. '
              'Nothing is read until you choose one.',
      actionLabel: vm.isBusy ? null : 'Look again',
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
      actionLabel: 'Back to cards',
      onAction: vm.backToVolumes,
    );
  }

  Widget _complete(AppColors colors) {
    final report = vm.report;
    // A run cut short by the card leaving must not say "safe to remove" — the
    // rest of the photos are still on it, and their rows were rolled back so
    // reinserting and scanning again really does pick them up (spec §9A).
    if (report != null && report.stoppedOnCardRemoval) {
      return IngestMessagePanel(
        appColors: colors,
        icon: Icons.warning_amber_outlined,
        tone: colors.warningColor,
        title: 'Card removed',
        detail: 'Imported ${report.imported} of ${vm.importTotal}. '
            'The rest are still on the card — reinsert it and scan again '
            'to continue.',
        actionLabel: 'Done',
        onAction: vm.done,
      );
    }
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

  /// The three ways a scan can come back with nothing to import.
  ///
  /// They read identically to an operator unless they are told apart, and each
  /// one calls for a different action.
  Widget _nothingToImport(AppColors colors, IngestScanResult scan) {
    // Photos exist but sit outside DCIM. Offering only a message here would
    // make them unreachable, so the folder list is shown instead.
    if (scan.onlyOutsideScope) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IngestMessagePanel(
            appColors: colors,
            icon: Icons.folder_open,
            title: 'Nothing in DCIM',
            detail: '${scan.outsideScanFolders} photos are on this card, '
                'but outside the folders being scanned. '
                'Tick a folder below to include it.',
          ),
          IngestFolderList(
            appColors: colors,
            folders: scan.folders,
            isIncluded: vm.isFolderIncluded,
            onToggle: vm.toggleFolder,
          ),
          const SizedBox(height: 16),
        ],
      );
    }

    final (title, detail) = switch (scan) {
      _ when scan.isEmptyCard => (
          'Card is empty',
          'This card has no photos on it yet.',
        ),
      _ when scan.isRawOnly => (
          'Only RAW files found',
          '${scan.skippedRaw} RAW files are on this card. '
              'Only JPEG, HEIC and PNG can be imported.',
        ),
      _ => (
          'Nothing new',
          'All ${scan.alreadyImported} photos on this card '
              'have already been imported.',
        ),
    };

    return IngestMessagePanel(
      appColors: colors,
      icon: scan.isEmptyCard ? Icons.sd_card_outlined : Icons.done_all,
      title: title,
      detail: detail,
      actionLabel: 'Scan again',
      onAction: vm.rescan,
    );
  }

  Widget _review(AppColors colors) {
    final scan = vm.scan;
    final settings = vm.settings;
    if (scan == null || settings == null) return const SizedBox.shrink();

    if (!scan.hasNew) return _nothingToImport(colors, scan);

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
