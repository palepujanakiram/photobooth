import 'package:flutter/material.dart';

import '../../services/event_pipeline/ingest/ingest_diff.dart';
import '../../services/event_pipeline/ingest/ingest_source.dart';
import '../../services/event_pipeline/ingest/ingest_worker.dart';
import '../../views/widgets/app_colors.dart';
import 'event_pipeline_settings_rows.dart';

/// Centred message with an optional action, for the empty and terminal states.
class IngestMessagePanel extends StatelessWidget {
  const IngestMessagePanel({
    super.key,
    required this.appColors,
    required this.icon,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
    this.tone,
  });

  final AppColors appColors;
  final IconData icon;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: tone ?? appColors.secondaryTextColor),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: appColors.textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(color: appColors.secondaryTextColor),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Live scan state.
///
/// Shows the count climbing **and** says it is still scanning, because a card
/// mounts with zero rows and fills in over seconds — a bare number would read as
/// a final answer while the scanner is still working.
class IngestScanningPanel extends StatelessWidget {
  const IngestScanningPanel({
    super.key,
    required this.appColors,
    required this.count,
  });

  final AppColors appColors;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            count == 0 ? 'Reading card…' : '$count photos found',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: appColors.textColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Still scanning — the count is not final yet.',
            style: TextStyle(color: appColors.secondaryTextColor),
          ),
        ],
      ),
    );
  }
}

/// "412 new · 1,088 already imported", plus any skipped-type explanation.
class IngestSummaryBar extends StatelessWidget {
  const IngestSummaryBar({
    super.key,
    required this.appColors,
    required this.result,
  });

  final AppColors appColors;
  final IngestScanResult result;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${result.newCandidates.length} new · '
          '${result.alreadyImported} already imported',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: appColors.textColor,
          ),
        ),
        if (result.skippedRaw > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              // Said explicitly so a RAW-only card is never mistaken for a
              // failed scan.
              '${result.skippedRaw} RAW files skipped — '
              'only JPEG, HEIC and PNG are imported.',
              style: TextStyle(
                fontSize: 12,
                color: appColors.secondaryTextColor,
              ),
            ),
          ),
      ],
    );
  }
}

/// Folder list with counts, DCIM pre-ticked and the rest opt-in.
class IngestFolderList extends StatelessWidget {
  const IngestFolderList({
    super.key,
    required this.appColors,
    required this.folders,
    required this.isIncluded,
    required this.onToggle,
  });

  final AppColors appColors;
  final List<IngestFolderSummary> folders;
  final bool Function(IngestFolderSummary) isIncluded;
  final void Function(IngestFolderSummary) onToggle;

  @override
  Widget build(BuildContext context) {
    if (folders.length <= 1) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Folders on this card',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: appColors.secondaryTextColor,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final folder in folders)
              FilterChip(
                label: Text('${folder.folder} · ${folder.total}'),
                selected: isIncluded(folder),
                // A default folder cannot be unticked — narrowing below the
                // configured scope belongs in settings, not mid-import.
                onSelected: folder.selectedByDefault
                    ? null
                    : (_) => onToggle(folder),
              ),
          ],
        ),
      ],
    );
  }
}

/// Grid of new photos with per-item selection.
///
/// Deliberately renders names and metadata, not thumbnails: decoding 412 JPEGs
/// off a card to paint a grid is the same memory mistake the old import tray
/// made, and the operator is triaging by folder and time, not by looking.
class IngestCandidateGrid extends StatelessWidget {
  const IngestCandidateGrid({
    super.key,
    required this.appColors,
    required this.candidates,
    required this.isSelected,
    required this.onToggle,
  });

  final AppColors appColors;
  final List<IngestCandidate> candidates;
  final bool Function(IngestCandidate) isSelected;
  final void Function(IngestCandidate) onToggle;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: candidates.length,
      itemExtent: 56,
      itemBuilder: (context, index) {
        final candidate = candidates[index];
        final selected = isSelected(candidate);
        return CheckboxListTile(
          dense: true,
          value: selected,
          onChanged: (_) => onToggle(candidate),
          title: Text(
            candidate.displayName,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: appColors.textColor),
          ),
          subtitle: Text(
            '${candidate.folder} · ${_sizeLabel(candidate.sizeBytes)}',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: appColors.secondaryTextColor,
            ),
          ),
        );
      },
    );
  }

  static String _sizeLabel(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).round()} KB';
  }
}

/// Footer: what will happen, and the button that commits it.
///
/// The chain is spelled out before the tap because [importSelected] is what
/// freezes those steps onto every selected item — after this, a settings change
/// will not alter them.
class IngestActionBar extends StatelessWidget {
  const IngestActionBar({
    super.key,
    required this.appColors,
    required this.steps,
    required this.copies,
    required this.printSize,
    required this.selectedCount,
    required this.onSelectAll,
    required this.onSelectNone,
    required this.onImport,
    this.enabled = true,
  });

  final AppColors appColors;
  final List<String> steps;
  final int copies;
  final String printSize;
  final int selectedCount;
  final VoidCallback onSelectAll;
  final VoidCallback onSelectNone;
  final VoidCallback onImport;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          EventPipelineChainPreview.describe(steps, copies, printSize),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: appColors.secondaryTextColor,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton(onPressed: enabled ? onSelectAll : null, child: const Text('All')),
            TextButton(onPressed: enabled ? onSelectNone : null, child: const Text('None')),
            const Spacer(),
            ElevatedButton(
              onPressed: enabled && selectedCount > 0 ? onImport : null,
              child: Text(
                selectedCount == 0
                    ? 'Import'
                    : 'Import $selectedCount',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Import progress, one image at a time.
class IngestProgressPanel extends StatelessWidget {
  const IngestProgressPanel({
    super.key,
    required this.appColors,
    required this.progress,
  });

  final AppColors appColors;
  final IngestProgress progress;

  @override
  Widget build(BuildContext context) {
    final fraction =
        progress.total == 0 ? 0.0 : progress.done / progress.total;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Importing ${progress.done} of ${progress.total}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: appColors.textColor,
              ),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: fraction),
            const SizedBox(height: 12),
            Text(
              'Do not remove the card yet.',
              style: TextStyle(color: appColors.secondaryTextColor),
            ),
          ],
        ),
      ),
    );
  }
}
