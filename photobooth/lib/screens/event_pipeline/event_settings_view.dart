import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_scaffold.dart';
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
          if (vm.needsFrameDownload)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed:
                      vm.isDownloadingFrames ? null : vm.downloadFrames,
                  child: Text(
                    vm.isDownloadingFrames
                        ? 'Downloading…'
                        : 'Download frame artwork',
                  ),
                ),
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
        ],
      ),
    );
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
