import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, visibleForTesting;
import 'package:uvccamera/uvccamera.dart';

/// Single upstream listener for [UvcCamera.deviceEventStream].
///
/// Multiple screens must not subscribe to the platform stream directly: when one
/// route pops and cancels its subscription, the EventChannel's native `onCancel`
/// can stop hotplug events for still-mounted routes.
class UvcDeviceEventHub {
  UvcDeviceEventHub._();

  static final UvcDeviceEventHub instance = UvcDeviceEventHub._();

  final StreamController<UvcCameraDeviceEvent> _controller =
      StreamController<UvcCameraDeviceEvent>.broadcast();

  StreamSubscription<UvcCameraDeviceEvent>? _upstream;
  bool _upstreamAttached = false;

  Stream<UvcCameraDeviceEvent>? _testUpstream;

  /// Broadcast fan-out; cancelling a returned subscription does not stop USB events.
  Stream<UvcCameraDeviceEvent> get stream {
    _ensureUpstream();
    return _controller.stream;
  }

  StreamSubscription<UvcCameraDeviceEvent> listen(
    void Function(UvcCameraDeviceEvent event) onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    _ensureUpstream();
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  void _ensureUpstream() {
    if (_upstreamAttached) return;
    final source = _resolveUpstream();
    if (source == null) return;
    _upstreamAttached = true;
    _upstream = source.listen(
      _controller.add,
      onError: _controller.addError,
      cancelOnError: false,
    );
  }

  Stream<UvcCameraDeviceEvent>? _resolveUpstream() {
    if (_testUpstream != null) return _testUpstream;
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    return UvcCamera.deviceEventStream;
  }

  @visibleForTesting
  set testUpstream(Stream<UvcCameraDeviceEvent> stream) {
    resetForTest();
    _testUpstream = stream;
  }

  @visibleForTesting
  void resetForTest() {
    _upstream?.cancel();
    _upstream = null;
    _upstreamAttached = false;
    _testUpstream = null;
  }
}
