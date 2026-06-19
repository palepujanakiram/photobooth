import 'dart:async';

import 'package:camera/camera.dart' show XFile;
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:uvccamera/uvccamera.dart';

import '../../services/error_reporting/error_reporting_manager.dart';
import '../../utils/logger.dart';
import 'photo_capture_viewmodel.dart';

class PhotoCaptureUvcScreen extends StatefulWidget {
  const PhotoCaptureUvcScreen({
    super.key,
    required this.viewModel,
    required this.device,
  });

  final CaptureViewModel viewModel;
  final UvcCameraDevice device;

  @override
  State<PhotoCaptureUvcScreen> createState() => _PhotoCaptureUvcScreenState();
}

class _PhotoCaptureUvcScreenState extends State<PhotoCaptureUvcScreen> {
  UvcCameraController? _controller;
  StreamSubscription<UvcCameraDeviceEvent>? _deviceEventsSub;
  bool _isInitializing = true;
  String? _error;
  UvcCameraResolutionPreset _preset = UvcCameraResolutionPreset.low;
  int _initAttempt = 0;

  @override
  void initState() {
    super.initState();
    // Start conservative. We'll allow bumping up and also auto-fallback lower on failures.
    _controller = _buildController(_preset);
    _attachDeviceEvents();
    unawaited(_init());
  }

  UvcCameraController _buildController(UvcCameraResolutionPreset preset) {
    return UvcCameraController(
      device: widget.device,
      resolutionPreset: preset,
    );
  }

  void _attachDeviceEvents() {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _deviceEventsSub?.cancel();
    _deviceEventsSub = UvcCamera.deviceEventStream.listen((e) {
      final isSameDevice = e.device.vendorId == widget.device.vendorId &&
          e.device.productId == widget.device.productId &&
          e.device.name == widget.device.name;
      if (!isSameDevice) return;
      AppLogger.debug(
        '📡 UVC screen device event: ${e.type.name} '
        'name="${e.device.name}" vid=${e.device.vendorId} pid=${e.device.productId}',
      );
      if (e.type.name == 'disconnected' || e.type.name == 'detached') {
        if (!mounted) return;
        setState(() {
          _error = 'USB camera disconnected.';
        });
        // Close the screen so the user can retry after reconnecting.
        Future<void>.delayed(const Duration(milliseconds: 350), () {
          if (!mounted) return;
          Navigator.pop(context, false);
        });
      }
    }, onError: (err, st) {
      AppLogger.error('UVC screen deviceEventStream error', error: err, stackTrace: st);
    });
  }

  Future<void> _init() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      setState(() {
        _isInitializing = false;
        _error = 'USB camera is only supported on Android.';
      });
      return;
    }

    try {
      _initAttempt++;
      setState(() {
        _isInitializing = true;
        _error = null;
      });
      unawaited(ErrorReportingManager.setCustomKeys({
        'uvc_open_vendorId': widget.device.vendorId,
        'uvc_open_productId': widget.device.productId,
        'uvc_open_name': widget.device.name,
        'uvc_open_preset': _preset.name,
        'uvc_open_attempt': _initAttempt,
      }));
      final ok = await UvcCamera.requestDevicePermission(widget.device);
      if (!ok) {
        setState(() {
          _isInitializing = false;
          _error = 'USB camera permission was not granted.';
        });
        return;
      }

      final ctrl = _controller;
      if (ctrl == null) {
        throw StateError('UVC controller is null');
      }
      await ctrl.initialize();
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _error = null;
      });
      AppLogger.debug(
        '✅ UVC initialized preset=${_preset.name} '
        'aspect=${ctrl.value.previewMode?.aspectRatio}',
      );
    } catch (e) {
      AppLogger.error('UVC init failed', error: e);
      unawaited(
        ErrorReportingManager.recordError(
          e,
          StackTrace.current,
          reason: 'UVC init failed',
          fatal: false,
        ),
      );
      if (!mounted) return;
      // Auto-fallback to a smaller preset before giving up.
      final nextPreset = switch (_preset) {
        UvcCameraResolutionPreset.medium => UvcCameraResolutionPreset.low,
        UvcCameraResolutionPreset.low => UvcCameraResolutionPreset.min,
        _ => null,
      };
      if (nextPreset != null) {
        AppLogger.debug(
          '↘️ UVC init failed at preset=${_preset.name}; retrying at ${nextPreset.name}',
        );
        await _recreateController(nextPreset);
        if (!mounted) return;
        await _init();
        return;
      }
      setState(() {
        _isInitializing = false;
        _error = 'Failed to initialize USB camera (min preset): $e';
      });
    }
  }

  Future<void> _recreateController(UvcCameraResolutionPreset preset) async {
    final old = _controller;
    _controller = null;
    _preset = preset;
    try {
      await old?.dispose();
    } catch (_) {
      // Best-effort.
    }
    _controller = _buildController(preset);
  }

  Future<void> _setPreset(UvcCameraResolutionPreset preset) async {
    if (_preset == preset) return;
    setState(() {
      _error = null;
      _isInitializing = true;
    });
    await _recreateController(preset);
    if (!mounted) return;
    await _init();
  }

  @override
  void dispose() {
    _deviceEventsSub?.cancel();
    _deviceEventsSub = null;
    final ctrl = _controller;
    _controller = null;
    if (ctrl != null) {
      unawaited(ctrl.dispose());
    }
    super.dispose();
  }

  Future<void> _takePicture() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    try {
      final XFile raw = await ctrl.takePicture();
      await widget.viewModel.setCapturedPhotoFromExternalFile(
        rawFile: raw,
        cameraId:
            'uvc:${widget.device.vendorId}:${widget.device.productId}:${widget.device.name}',
      );
      // Release UVC resources before returning to the capture screen.
      await ctrl.dispose();
      _controller = null;
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      AppLogger.error('UVC takePicture failed', error: e);
      if (!mounted) return;
      setState(() {
        _error = 'USB camera capture failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text('USB Camera (${_preset.name})'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.xmark),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _isInitializing
                    ? const CircularProgressIndicator()
                    : (_error != null)
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                            ),
                          )
                        : (ctrl == null ? const SizedBox.shrink() : _safePreview(ctrl)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isInitializing
                          ? null
                          : () => unawaited(_setPreset(UvcCameraResolutionPreset.min)),
                      child: const Text('Min'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isInitializing
                          ? null
                          : () => unawaited(_setPreset(UvcCameraResolutionPreset.low)),
                      child: const Text('Low'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isInitializing
                          ? null
                          : () => unawaited(_setPreset(UvcCameraResolutionPreset.medium)),
                      child: const Text('Med'),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isInitializing || _error != null
                      ? null
                      : () => unawaited(_takePicture()),
                  icon: const Icon(CupertinoIcons.camera),
                  label: const Text('Capture'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _safePreview(UvcCameraController controller) {
    if (!controller.value.isInitialized) return const SizedBox.shrink();
    final previewMode = controller.value.previewMode;
    final aspect = previewMode?.aspectRatio ?? 1.0;
    return AspectRatio(
      aspectRatio: aspect <= 0 ? 1.0 : aspect,
      child: controller.buildPreview(),
    );
  }
}

