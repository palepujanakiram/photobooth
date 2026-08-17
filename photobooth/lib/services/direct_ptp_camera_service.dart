import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/logger.dart';

/// Connection state of the DSLR, mirrored from Kotlin `ConnectionState`.
///
/// The native side owns the real state machine; this is the subset Dart needs to
/// decide what to show. [unknown] covers a native state this build does not know
/// about — forward compatibility matters here because the Kotlin enum will grow
/// (live view, downloading) before the Dart side has any use for the new values.
enum DirectPtpState {
  noUsbHost,
  noDevice,
  deviceFound,
  permissionDenied,
  opened,
  sessionOpen,
  remoteMode,
  ready,
  busy,
  downloading,
  liveView,
  wedged,
  recovering,
  detached,
  error,
  unknown;

  /// Healthy enough to attempt a capture.
  bool get isOperational =>
      this == ready ||
      this == busy ||
      this == downloading ||
      this == liveView ||
      this == remoteMode;

  /// Warrants a red indicator rather than amber or green.
  bool get isFault =>
      this == error ||
      this == wedged ||
      this == permissionDenied ||
      this == noUsbHost;
}

/// Maps the Kotlin sealed-class simple names onto [DirectPtpState].
DirectPtpState directPtpStateFromName(String? name) {
  switch (name) {
    case 'NoUsbHostSupport':
      return DirectPtpState.noUsbHost;
    case 'NoDevice':
      return DirectPtpState.noDevice;
    case 'DeviceFound':
      return DirectPtpState.deviceFound;
    case 'PermissionDenied':
      return DirectPtpState.permissionDenied;
    case 'Opened':
      return DirectPtpState.opened;
    case 'SessionOpen':
      return DirectPtpState.sessionOpen;
    case 'RemoteMode':
      return DirectPtpState.remoteMode;
    case 'Ready':
      return DirectPtpState.ready;
    case 'Busy':
      return DirectPtpState.busy;
    case 'Downloading':
      return DirectPtpState.downloading;
    case 'LiveView':
      return DirectPtpState.liveView;
    case 'Wedged':
      return DirectPtpState.wedged;
    case 'Recovering':
      return DirectPtpState.recovering;
    case 'Detached':
      return DirectPtpState.detached;
    case 'Error':
      return DirectPtpState.error;
    default:
      return DirectPtpState.unknown;
  }
}

/// A snapshot of the camera link.
@immutable
class DirectPtpStatus {
  const DirectPtpStatus({
    required this.state,
    this.label = '',
    this.productName,
    this.message,
    this.timedOut = false,
  });

  /// Builds from the native status map; tolerates missing keys.
  factory DirectPtpStatus.fromMap(Map<Object?, Object?> map) {
    return DirectPtpStatus(
      state: directPtpStateFromName(map['state'] as String?),
      label: (map['label'] as String?) ?? '',
      productName: map['productName'] as String?,
      message: map['message'] as String?,
      timedOut: map['timedOut'] == true,
    );
  }

  final DirectPtpState state;
  final String label;

  /// Camera model as reported by the body, e.g. `Canon EOS 200D II`.
  final String? productName;

  /// Failure detail for [DirectPtpState.error] / [DirectPtpState.wedged].
  final String? message;

  /// Connect gave up waiting; [state] is the last state actually observed.
  final bool timedOut;

  bool get isOperational => state.isOperational;
  bool get isFault => state.isFault;

  @override
  String toString() =>
      'DirectPtpStatus(${state.name}, label: $label, '
      'product: $productName, timedOut: $timedOut)';

  @override
  bool operator ==(Object other) =>
      other is DirectPtpStatus &&
      other.state == state &&
      other.label == label &&
      other.productName == productName &&
      other.message == message &&
      other.timedOut == timedOut;

  @override
  int get hashCode => Object.hash(state, label, productName, message, timedOut);
}

/// What is physically on the USB bus, without opening it.
@immutable
class DirectPtpDevice {
  const DirectPtpDevice({
    required this.deviceName,
    required this.vendorId,
    required this.productId,
    this.manufacturer,
    this.product,
    this.hasPermission = false,
  });

  factory DirectPtpDevice.fromMap(Map<Object?, Object?> map) {
    return DirectPtpDevice(
      deviceName: (map['deviceName'] as String?) ?? '',
      vendorId: (map['vendorId'] as int?) ?? 0,
      productId: (map['productId'] as int?) ?? 0,
      manufacturer: map['manufacturer'] as String?,
      product: map['product'] as String?,
      hasPermission: map['hasPermission'] == true,
    );
  }

  final String deviceName;
  final int vendorId;
  final int productId;
  final String? manufacturer;
  final String? product;
  final bool hasPermission;

  @override
  String toString() =>
      'DirectPtpDevice($product, vid: 0x${vendorId.toRadixString(16)}, '
      'pid: 0x${productId.toRadixString(16)}, permission: $hasPermission)';
}

/// How a native capture session ended.
enum DirectPtpCaptureStatus { completed, cancelled, error, unknown }

DirectPtpCaptureStatus _captureStatusFromName(String? name) {
  switch (name) {
    case 'completed':
      return DirectPtpCaptureStatus.completed;
    case 'cancelled':
      return DirectPtpCaptureStatus.cancelled;
    case 'error':
      return DirectPtpCaptureStatus.error;
    default:
      return DirectPtpCaptureStatus.unknown;
  }
}

/// One photo taken by the native capture screen.
///
/// Both fields are **paths**, never bytes. The original is a ~6.5 MB, 6000×4000
/// JPEG — around 96 MB once decoded — so it is never read into Dart. Use
/// [displayPath] for anything on screen or uploaded, and [originalPath] only for
/// printing, where the native side decodes it subsampled.
@immutable
class DirectPtpShot {
  const DirectPtpShot({
    required this.originalPath,
    this.displayPath,
    this.widthPx = 0,
    this.heightPx = 0,
    this.bytes = 0,
    this.capturedAtMs = 0,
  });

  factory DirectPtpShot.fromMap(Map<Object?, Object?> map) {
    return DirectPtpShot(
      originalPath: (map['originalPath'] as String?) ?? '',
      displayPath: map['displayPath'] as String?,
      widthPx: (map['widthPx'] as int?) ?? 0,
      heightPx: (map['heightPx'] as int?) ?? 0,
      bytes: (map['bytes'] as num?)?.toInt() ?? 0,
      capturedAtMs: (map['capturedAtMs'] as num?)?.toInt() ?? 0,
    );
  }

  /// Untouched camera JPEG. Print from this.
  final String originalPath;

  /// Downscaled copy for review and upload. Null when the derivative failed —
  /// the original is still on disk, so this costs a thumbnail, not the photo.
  final String? displayPath;

  final int widthPx;
  final int heightPx;
  final int bytes;
  final int capturedAtMs;

  /// Best path to show on screen without risking a full-resolution decode.
  String get previewPath => displayPath ?? originalPath;

  @override
  String toString() =>
      'DirectPtpShot($originalPath, ${widthPx}x$heightPx, $bytes bytes)';
}

/// Outcome of a native capture session.
@immutable
class DirectPtpCaptureResult {
  const DirectPtpCaptureResult({
    required this.status,
    this.shots = const <DirectPtpShot>[],
    this.errorCode,
    this.errorMessage,
  });

  factory DirectPtpCaptureResult.fromMap(Map<Object?, Object?> map) {
    final rawShots = map['shots'];
    final shots = rawShots is List
        ? rawShots
            .whereType<Map<Object?, Object?>>()
            .map(DirectPtpShot.fromMap)
            .toList()
        : const <DirectPtpShot>[];
    return DirectPtpCaptureResult(
      status: _captureStatusFromName(map['status'] as String?),
      shots: shots,
      errorCode: map['errorCode'] as String?,
      errorMessage: map['errorMessage'] as String?,
    );
  }

  final DirectPtpCaptureStatus status;
  final List<DirectPtpShot> shots;

  /// Stable code for the failure: `no_device`, `permission_denied`,
  /// `card_unavailable`, `camera_busy`, … Each maps to a different operator
  /// action, which is why it is separate from [errorMessage].
  final String? errorCode;
  final String? errorMessage;

  bool get isCompleted =>
      status == DirectPtpCaptureStatus.completed && shots.isNotEmpty;
  bool get isCancelled => status == DirectPtpCaptureStatus.cancelled;

  @override
  String toString() =>
      'DirectPtpCaptureResult(${status.name}, ${shots.length} shots, '
      'code: $errorCode)';
}

/// Dart side of the direct-PTP DSLR bridge (`CanonPtpMethodChannel`).
///
/// Connection lifecycle only. Capture and live view never cross this channel —
/// they belong to the native capture screen, because a 6000×4000 JPEG is ~96 MB
/// decoded and moving frames through a platform channel is the cost the whole
/// design exists to avoid. See `docs/direct-ptp-native-camera-plan.md`.
class DirectPtpCameraService {
  DirectPtpCameraService({
    MethodChannel? channel,
    EventChannel? statusChannel,
    bool Function()? isAndroid,
  })  : _channel = channel ?? const MethodChannel(methodChannelName),
        _statusChannel =
            statusChannel ?? const EventChannel(statusChannelName),
        _isAndroid = isAndroid ?? (() => !kIsWeb && Platform.isAndroid);

  static const String methodChannelName = 'com.srisarani.fotozenai/canon_ptp';
  static const String statusChannelName =
      'com.srisarani.fotozenai/canon_ptp_status';

  final MethodChannel _channel;
  final EventChannel _statusChannel;
  final bool Function() _isAndroid;

  /// True only where a native bridge exists — web and iOS have no PTP path.
  bool get isSupported => !kIsWeb && _isAndroid();

  /// Whether this hardware can act as a USB host at all (`U-07`).
  ///
  /// A false here is terminal for the direct-PTP path: no amount of retrying or
  /// recabling helps, and the booth must fall back to another camera source.
  Future<bool> hasUsbHost() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('hasUsbHost') ?? false;
    } catch (e) {
      AppLogger.warning('Direct PTP hasUsbHost failed: $e');
      return false;
    }
  }

  /// The attached camera, or null when nothing suitable is on the bus.
  ///
  /// Distinct from [connect] so a booth can tell "no camera plugged in" from
  /// "camera present, permission refused" — one needs a cable, the other needs a
  /// dialog answered, and showing the same message for both wastes an operator's
  /// time.
  Future<DirectPtpDevice?> probeDevice() async {
    if (!isSupported) return null;
    try {
      final map = await _channel
          .invokeMapMethod<Object?, Object?>('probeDevice');
      if (map == null) return null;
      return DirectPtpDevice.fromMap(map);
    } catch (e) {
      AppLogger.warning('Direct PTP probeDevice failed: $e');
      return null;
    }
  }

  /// Opens USB, the PTP session and Canon remote mode.
  ///
  /// Resolves once the link reaches a settled state; a slow negotiation comes
  /// back with [DirectPtpStatus.timedOut] set rather than throwing, because
  /// "still negotiating" and "refused" call for different operator responses.
  Future<DirectPtpStatus> connect() async {
    if (!isSupported) {
      return const DirectPtpStatus(
        state: DirectPtpState.noUsbHost,
        label: 'Direct PTP unsupported on this platform',
      );
    }
    try {
      final map = await _channel.invokeMapMethod<Object?, Object?>('connect');
      final status = map == null
          ? const DirectPtpStatus(state: DirectPtpState.unknown)
          : DirectPtpStatus.fromMap(map);
      AppLogger.info('Direct PTP connect → $status');
      return status;
    } catch (e) {
      AppLogger.warning('Direct PTP connect failed: $e');
      return DirectPtpStatus(
        state: DirectPtpState.error,
        label: 'Connect failed',
        message: '$e',
      );
    }
  }

  /// Current link state without changing it.
  Future<DirectPtpStatus> status() async {
    if (!isSupported) {
      return const DirectPtpStatus(state: DirectPtpState.noUsbHost);
    }
    try {
      final map = await _channel.invokeMapMethod<Object?, Object?>('status');
      if (map == null) return const DirectPtpStatus(state: DirectPtpState.unknown);
      return DirectPtpStatus.fromMap(map);
    } catch (e) {
      AppLogger.warning('Direct PTP status failed: $e');
      return DirectPtpStatus(
        state: DirectPtpState.error,
        label: 'Status failed',
        message: '$e',
      );
    }
  }

  /// Opens the native capture screen and waits for it to finish.
  ///
  /// The returned Future spans the whole session — connect, live view, every
  /// shot, download and derivative — because the native screen owns all of it.
  /// Nothing but paths comes back.
  ///
  /// Never throws: a failure arrives as [DirectPtpCaptureStatus.error] with a
  /// code, so the capture flow has one place to handle every outcome.
  Future<DirectPtpCaptureResult> runCaptureSession({
    int shotCount = 1,
    int countdownSeconds = 10,
    int betweenShotSeconds = 8,
    int displayMaxLongEdge = 1920,
    int displayJpegQuality = 90,
    int idleTimeoutSeconds = 180,
    String? titleText,
    String? subtitleText,
    String? shutterText,
    String? cancelText,
  }) async {
    if (!isSupported) {
      return const DirectPtpCaptureResult(
        status: DirectPtpCaptureStatus.error,
        errorCode: 'unsupported_platform',
        errorMessage: 'Direct PTP capture needs Android USB host',
      );
    }
    try {
      final map = await _channel.invokeMapMethod<Object?, Object?>(
        'runCaptureSession',
        <String, Object?>{
          'shotCount': shotCount,
          'countdownSeconds': countdownSeconds,
          'betweenShotSeconds': betweenShotSeconds,
          'displayMaxLongEdge': displayMaxLongEdge,
          'displayJpegQuality': displayJpegQuality,
          'idleTimeoutSeconds': idleTimeoutSeconds,
          'titleText': titleText,
          'subtitleText': subtitleText,
          'shutterText': shutterText,
          'cancelText': cancelText,
        },
      );
      final result = map == null
          ? const DirectPtpCaptureResult(status: DirectPtpCaptureStatus.unknown)
          : DirectPtpCaptureResult.fromMap(map);
      AppLogger.info('Direct PTP capture session → $result');
      return result;
    } catch (e) {
      AppLogger.warning('Direct PTP capture session failed: $e');
      return DirectPtpCaptureResult(
        status: DirectPtpCaptureStatus.error,
        errorCode: 'capture_failed',
        errorMessage: '$e',
      );
    }
  }

  /// Releases the camera. Best-effort — never throws.
  Future<void> disconnect() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('disconnect');
    } catch (e) {
      AppLogger.debug('Direct PTP disconnect failed: $e');
    }
  }

  /// Link state as it changes, for status UI that should not poll.
  Stream<DirectPtpStatus> statusStream() {
    if (!isSupported) return const Stream<DirectPtpStatus>.empty();
    return _statusChannel.receiveBroadcastStream().map((event) {
      if (event is Map) return DirectPtpStatus.fromMap(event);
      return const DirectPtpStatus(state: DirectPtpState.unknown);
    });
  }
}
