import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/app_strings.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_scaffold.dart';
import '../event_station/event_station_chrome_view_widgets.dart';
import 'event_capture_viewmodel.dart';

/// Tethered capture for the event pipeline.
///
/// Distinct from the guest capture station: there is no countdown and no
/// consent flow, because the person in front of this screen is the operator.
/// CCAPI plugs in behind [EventCaptureSource] later without this screen
/// changing.
class EventCaptureScreen extends StatelessWidget {
  const EventCaptureScreen({super.key, this.viewModel});

  final EventCaptureViewModel? viewModel;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<EventCaptureViewModel>(
      create: (_) => (viewModel ?? EventCaptureViewModel())..start(),
      child: Consumer<EventCaptureViewModel>(
        builder: (context, vm, _) => AppScaffold(
          title: AppStrings.eventHubCapture,
          showBackButton: true,
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(
                  vm.cameraName ?? 'No camera',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
          child: EventStationBoundShell(child: _CaptureBody(vm: vm)),
        ),
      ),
    );
  }
}

class _CaptureBody extends StatelessWidget {
  const _CaptureBody({required this.vm});

  final EventCaptureViewModel vm;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (vm.phase == CapturePhase.noCamera) {
      return _noCamera(colors);
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _stage(colors)),
          if (vm.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                vm.errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: colors.errorColor),
              ),
            ),
          const SizedBox(height: 12),
          _RecentStrip(vm: vm, colors: colors),
          const SizedBox(height: 12),
          _controls(context, colors),
        ],
      ),
    );
  }

  Widget _noCamera(AppColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_camera_outlined,
                size: 56, color: colors.secondaryTextColor),
            const SizedBox(height: 16),
            Text(
              'No camera connected',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: colors.textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Connect the camera over USB and make sure it is on and awake.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.secondaryTextColor),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: vm.refreshCamera,
              child: const Text('Look again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stage(AppColors colors) {
    final shot = vm.pendingShot;
    if (shot != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(shot.displayPath),
          fit: BoxFit.contain,
          // The preview copy, decoded small. The original is a 6000×4000 frame
          // and is never decoded in Dart at all.
          cacheWidth: 900,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => Container(
            color: colors.cardBackgroundColor,
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: colors.cardBackgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          vm.phase == CapturePhase.shooting ? 'Capturing…' : 'Ready',
          style: TextStyle(color: colors.secondaryTextColor),
        ),
      ),
    );
  }

  Widget _controls(BuildContext context, AppColors colors) {
    if (vm.pendingShot == null) {
      return ElevatedButton(
        onPressed: vm.canShoot ? vm.shoot : null,
        child: Text(vm.phase == CapturePhase.shooting ? '…' : 'Shutter'),
      );
    }
    // Confirm is the commit point; Retake writes nothing at all.
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: vm.isBusy ? null : vm.retake,
            child: const Text('Retake'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: vm.isBusy ? null : vm.confirm,
            child: Text(
              vm.phase == CapturePhase.committing ? 'Queueing…' : 'Confirm',
            ),
          ),
        ),
      ],
    );
  }
}

/// The last few committed frames, so a photographer can see work landing.
class _RecentStrip extends StatelessWidget {
  const _RecentStrip({required this.vm, required this.colors});

  final EventCaptureViewModel vm;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final recent = vm.recentShots;
    if (recent.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          Text(
            'Recent',
            style: TextStyle(fontSize: 11, color: colors.secondaryTextColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: recent.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final file = recent[i].thumbnail;
                return ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 56,
                    child: file == null
                        ? Container(color: colors.cardBackgroundColor)
                        : Image.file(
                            file,
                            fit: BoxFit.cover,
                            cacheWidth: 120,
                            gaplessPlayback: true,
                            errorBuilder: (_, __, ___) =>
                                Container(color: colors.cardBackgroundColor),
                          ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
