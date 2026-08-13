import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/local_camera_service.dart';
import '../../services/sidecar_live_preview_poller.dart';
import '../../utils/app_strings.dart';

/// Pose live view from the Pi gphoto2 sidecar (polled JPEG frames).
class SidecarLivePreview extends StatefulWidget {
  const SidecarLivePreview({
    super.key,
    required this.service,
    this.paused = false,
    this.onFirstFrame,
    this.fit = BoxFit.cover,
  });

  final LocalCameraService service;
  final bool paused;
  final VoidCallback? onFirstFrame;
  final BoxFit fit;

  @override
  State<SidecarLivePreview> createState() => _SidecarLivePreviewState();
}

class _SidecarLivePreviewState extends State<SidecarLivePreview> {
  SidecarLivePreviewPoller? _poller;
  Uint8List? _frame;
  Object? _error;
  bool _notifiedFirstFrame = false;

  @override
  void initState() {
    super.initState();
    _startPoller();
  }

  @override
  void didUpdateWidget(covariant SidecarLivePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      _poller?.dispose();
      _startPoller();
    } else if (oldWidget.paused != widget.paused) {
      if (widget.paused) {
        _poller?.pause();
      } else {
        _poller?.resume();
      }
    }
  }

  void _startPoller() {
    _poller = SidecarLivePreviewPoller(
      service: widget.service,
      onFrame: (bytes) {
        if (!mounted) return;
        setState(() {
          _frame = bytes;
          _error = null;
        });
        if (!_notifiedFirstFrame) {
          _notifiedFirstFrame = true;
          widget.onFirstFrame?.call();
        }
      },
      onError: (err) {
        if (!mounted || _frame != null) return;
        if (isSidecarPreviewWarmingError(err)) return;
        setState(() => _error = err);
      },
    );
    if (widget.paused) {
      _poller!.pause();
    }
    _poller!.start();
  }

  @override
  void dispose() {
    _poller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    if (frame != null) {
      return SizedBox.expand(
        child: Image.memory(
          frame,
          fit: widget.fit,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        ),
      );
    }
    if (_error != null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            AppStrings.sidecarLivePreviewUnavailable,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(AppStrings.sidecarLivePreviewConnecting),
        ],
      ),
    );
  }
}
