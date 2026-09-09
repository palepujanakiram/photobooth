import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/constants.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_scaffold.dart';
import 'event_image_viewer.dart';
import 'event_settings_viewmodel.dart';

/// What this device is running the event on. Read-only, with one `Sync`.
///
/// Event settings live on ZenAI. The practical consequence is that getting an
/// event wrong is fixed on the backend and re-synced, not worked around on the
/// box — which is the right place for it to be fixed, but does mean a badly
/// configured event is blocked on backend access (spec §9).
class EventSettingsScreen extends StatelessWidget {
  const EventSettingsScreen({super.key, this.viewModel});

  final EventSettingsViewModel? viewModel;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<EventSettingsViewModel>(
      create: (_) => (viewModel ?? EventSettingsViewModel())..start(),
      child: Consumer<EventSettingsViewModel>(
        builder: (context, vm, _) => AppScaffold(
          title: 'Event settings',
          showBackButton: true,
          actions: [
            TextButton(
              onPressed: vm.isBusy ? null : vm.sync,
              child: const Text('Sync'),
            ),
          ],
          child: _SettingsBody(vm: vm),
        ),
      ),
    );
  }
}

class _SettingsBody extends StatelessWidget {
  const _SettingsBody({required this.vm});

  final EventSettingsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (vm.settings == null) {
      return Center(
        child: Text(
          'No settings on this device yet.',
          style: TextStyle(color: colors.secondaryTextColor),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  vm.syncedLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.secondaryTextColor,
                  ),
                ),
              ),
              Text(
                '(read only)',
                style: TextStyle(
                  fontSize: 11,
                  color: colors.secondaryTextColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final row in vm.rows) _SettingTile(row: row, colors: colors),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 4,
              children: [
                if (vm.needsFrameDownload)
                  TextButton(
                    onPressed:
                        vm.isDownloadingFrames ? null : vm.downloadFrames,
                    child: Text(
                      vm.isDownloadingFrames
                          ? 'Downloading…'
                          : 'Download frame artwork',
                    ),
                  ),
                // "1 cached" says a file exists, not that it is the right
                // artwork. Looking at it is the only way to know.
                if (vm.canPreviewFrame)
                  TextButton.icon(
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: const Text('View frame'),
                    onPressed: () => EventImageViewer.show(
                      context,
                      file: vm.frameImage!,
                      title: 'Event frame',
                      subtitle: vm.settings?.frameId,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colors.cardBackgroundColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Each photo will run',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.secondaryTextColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  vm.chainSummary,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _DangerZone(vm: vm, colors: colors),
        ],
      ),
    );
  }
}

/// Leaving the event, and clearing what it left behind.
///
/// Two separate actions on purpose. Leaving is what an operator does to hand
/// the tablet on or step out; clearing is what frees the disk. Folding them
/// together would mean every exit destroyed a night's work.
class _DangerZone extends StatelessWidget {
  const _DangerZone({required this.vm, required this.colors});

  final EventSettingsViewModel vm;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final blockers = vm.purgeBlockers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(color: colors.dividerColor),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: vm.isBusy ? null : () => _leave(context),
          child: const Text('Leave event'),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: Text(
            'Unbinds this device. Photos already imported stay on it.',
            style: TextStyle(fontSize: 11, color: colors.secondaryTextColor),
          ),
        ),
        OutlinedButton(
          onPressed: vm.isPurging ? null : () => _clear(context),
          style: OutlinedButton.styleFrom(foregroundColor: colors.errorColor),
          child: Text(vm.isPurging ? 'Clearing…' : 'Clear event data'),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            blockers.isEmpty
                ? "Deletes this event's photos and prints from the device. "
                    'Frees space for the next one.'
                // Named rather than blocked: the operator is told exactly what
                // they would destroy and decides.
                : 'Not finished yet — ${blockers.join(', ')}.',
            style: TextStyle(
              fontSize: 11,
              color: blockers.isEmpty
                  ? colors.secondaryTextColor
                  : colors.warningColor,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _leave(BuildContext context) async {
    final ok = await _confirm(
      context,
      title: 'Leave this event?',
      body: 'This device stops running the event. Photos already imported are '
          'left on it, and you can bind the event again.',
      action: 'Leave',
    );
    if (!ok || !context.mounted) return;
    await vm.leaveEvent();
    if (!context.mounted) return;
    // Back to the bind screen, which is where an unbound device belongs.
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppConstants.kRouteSplash,
      (route) => false,
    );
  }

  Future<void> _clear(BuildContext context) async {
    final blockers = vm.purgeBlockers;
    final ok = await _confirm(
      context,
      title: 'Clear this event\'s data?',
      body: blockers.isEmpty
          ? 'Every photo, print and derivative for this event is deleted from '
              'this device. This cannot be undone.'
          : 'Every photo, print and derivative for this event is deleted from '
              'this device, including work that has not finished — '
              '${blockers.join(', ')}. This cannot be undone.',
      action: 'Clear',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final removed = await vm.clearEventData();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Cleared $removed photos')),
    );
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String action,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: destructive
                ? TextButton.styleFrom(foregroundColor: colors.errorColor)
                : null,
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({required this.row, required this.colors});

  final EventSettingRow row;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colors.textColor,
                  ),
                ),
              ),
              Text(
                row.value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textColor,
                ),
              ),
            ],
          ),
          Text(
            row.subtitle,
            style: TextStyle(fontSize: 12, color: colors.secondaryTextColor),
          ),
          if (row.detail != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                row.detail!,
                style: TextStyle(fontSize: 12, color: colors.textColor),
              ),
            ),
          if (row.warning != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                row.warning!,
                style: TextStyle(fontSize: 12, color: colors.warningColor),
              ),
            ),
        ],
      ),
    );
  }
}
