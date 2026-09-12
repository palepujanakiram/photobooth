import 'package:flutter/services.dart';

import '../../utils/logger.dart';

/// Controls the native foreground service that keeps the queue running.
///
/// Dart timers are throttled once the app is backgrounded, so without the
/// service a long event stalls the moment the operator locks the phone. The
/// notification is the price Android charges for that, so it is only shown while
/// there is actually work — started when the queue fills, stopped when it drains.
class EventPipelineServiceChannel {
  EventPipelineServiceChannel({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName =
      'com.srisarani.fotozenai/event_pipeline_service';

  final MethodChannel _channel;

  bool _running = false;

  /// True when the foreground service is believed to be up.
  bool get isRunning => _running;

  /// Starts the service, or updates its text if already running.
  Future<void> start({required String status}) async {
    try {
      await _channel.invokeMethod<bool>('start', {'status': status});
      _running = true;
    } on PlatformException catch (e) {
      // A refused foreground service must not take the queue down with it: the
      // work still runs while the app is in front.
      AppLogger.warning('Pipeline service start failed: ${e.message}');
    } on MissingPluginException {
      // Non-Android or an older build — degrade to foreground-only processing.
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    try {
      await _channel.invokeMethod<bool>('stop');
    } on PlatformException catch (e) {
      AppLogger.debug('Pipeline service stop failed: ${e.message}');
    } on MissingPluginException {
      // Nothing to stop.
    }
    _running = false;
  }

  /// Lane and bitmap-permit snapshot, for the diagnostics panel.
  Future<Map<Object?, Object?>> lanes() async {
    try {
      return await _channel.invokeMapMethod<Object?, Object?>('lanes') ??
          const <Object?, Object?>{};
    } on PlatformException {
      return const <Object?, Object?>{};
    } on MissingPluginException {
      return const <Object?, Object?>{};
    }
  }
}
