import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android MethodChannel client for Canon Selphy CP1500 (USB + Wi‑Fi).
class SelphyClient {
  SelphyClient({
    MethodChannel? channel,
    bool Function()? isAndroid,
  })  : _channel = channel ?? const MethodChannel(_channelName),
        _isAndroid = isAndroid ?? (() => !kIsWeb && Platform.isAndroid);

  static const _channelName = 'com.srisarani.fotozenai/selphy';

  final MethodChannel _channel;
  final bool Function() _isAndroid;

  bool get isSupported => !kIsWeb && _isAndroid();

  /// True when a Selphy is visible on USB (no permission dialog).
  Future<bool> probeUsbPresent() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('probeUsb') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> ensureUsbConnected() async {
    await _channel.invokeMethod<void>('requestPermission');
  }

  /// Discovers the first Selphy on Wi‑Fi (binds process to Wi‑Fi first).
  Future<void> discoverWifi() async {
    await _channel.invokeMethod<void>('discoverWifi');
  }

  /// Releases Wi‑Fi process binding after discovery/print.
  Future<void> releaseWifi() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('releaseWifi');
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> resetSession() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('resetSession');
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> print({
    required String filePath,
    required String transport,
    required String paperSize,
    required int copies,
    String filter = 'Off',
    int brightness = 0,
    bool bordered = false,
  }) async {
    await _channel.invokeMethod<void>(
      'print',
      {
        'filePath': filePath,
        'transport': transport,
        'paperSize': paperSize,
        'copies': copies,
        'filter': filter,
        'brightness': brightness,
        'bordered': bordered,
      },
    );
  }
}
