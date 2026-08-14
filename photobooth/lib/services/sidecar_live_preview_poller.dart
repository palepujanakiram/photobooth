import 'dart:async';
import 'dart:typed_data';

import '../services/local_camera_service.dart';
import '../utils/logger.dart';

/// True when Canon EVF is still warming (503 / no frame) — keep connecting UI.
bool isSidecarPreviewWarmingError(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('503') || msg.contains('no frame');
}

/// Polls localhost `/camera/preview` for pose UI frames.
///
/// Prefer polling over MJPEG multipart: Flutter Android handles discrete JPEGs
/// reliably, and we can pause during tethered still capture so the sidecar is free.
class SidecarLivePreviewPoller {
  SidecarLivePreviewPoller({
    required LocalCameraService service,
    this.interval = const Duration(milliseconds: 350),
    void Function(Uint8List bytes)? onFrame,
    void Function(Object error)? onError,
  })  : _service = service,
        _onFrame = onFrame,
        _onError = onError;

  final LocalCameraService _service;
  final Duration interval;
  final void Function(Uint8List bytes)? _onFrame;
  final void Function(Object error)? _onError;

  Timer? _timer;
  bool _inFlight = false;
  bool _paused = false;
  bool _disposed = false;

  bool get isRunning => _timer != null;

  /// Keep polls short so a slow EVF download cannot freeze pose for seconds.
  static const Duration frameTimeout = Duration(milliseconds: 800);

  void start() {
    if (_disposed || _timer != null) return;
    _timer = Timer.periodic(interval, (_) => unawaited(_tick()));
    unawaited(_tick());
  }

  void pause() {
    _paused = true;
  }

  void resume() {
    _paused = false;
  }

  Future<void> _tick() async {
    if (_disposed || _paused || _inFlight) return;
    if (!_service.shouldShowLivePreview) return;
    _inFlight = true;
    try {
      final bytes = await _service.fetchPreviewJpeg(timeout: frameTimeout);
      if (_disposed || _paused) return;
      _onFrame?.call(bytes);
    } catch (e) {
      if (!_disposed) {
        AppLogger.warning('Sidecar live preview frame failed: $e');
        _onError?.call(e);
      }
    } finally {
      _inFlight = false;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
