import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/event_pipeline/capture/event_capture_source.dart';
import '../../utils/app_strings.dart';
import '../../views/widgets/app_colors.dart';

/// Live/review pane for event device capture.
class EventDeviceCapturePreview extends StatelessWidget {
  const EventDeviceCapturePreview({super.key, required this.shot});

  final CapturedShot? shot;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (shot == null) {
      return ColoredBox(
        color: colors.surfaceColor,
        child: Center(
          child: Text(
            AppStrings.eventHubCapture,
            style: TextStyle(color: colors.secondaryTextColor),
          ),
        ),
      );
    }
    final bytes = shot!.inlineBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(bytes, fit: BoxFit.contain);
    }
    if (!kIsWeb && shot!.originalPath.isNotEmpty) {
      return Image.file(File(shot!.originalPath), fit: BoxFit.contain);
    }
    return const SizedBox.shrink();
  }
}

/// Shutter / accept / retake / done row.
class EventDeviceCaptureActions extends StatelessWidget {
  const EventDeviceCaptureActions({
    super.key,
    required this.hasPending,
    required this.busy,
    required this.onShutter,
    required this.onAccept,
    required this.onRetake,
    required this.onDone,
  });

  final bool hasPending;
  final bool busy;
  final VoidCallback onShutter;
  final VoidCallback onAccept;
  final VoidCallback onRetake;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    if (hasPending) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: busy ? null : onRetake,
              child: const Text(AppStrings.eventDeviceCaptureRetake),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: busy ? null : onAccept,
              child: const Text(AppStrings.eventDeviceCaptureAccept),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onDone,
            child: const Text(AppStrings.eventDeviceCaptureDone),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: busy ? null : onShutter,
            child: const Text(AppStrings.eventHubCapture),
          ),
        ),
      ],
    );
  }
}
