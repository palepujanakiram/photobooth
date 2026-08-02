import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Android native USB channel for Posiflow / ESC/POS receipt printers.
class ReceiptUsbClient {
  ReceiptUsbClient({
    MethodChannel? channel,
    bool Function()? isAndroid,
    int? inlinePayloadLimit,
  })  : _channel = channel ?? const MethodChannel(_channelName),
        _isAndroid = isAndroid ?? (() => !kIsWeb && Platform.isAndroid),
        _inlinePayloadLimit = inlinePayloadLimit ?? _defaultInlinePayloadLimit;

  static const _channelName = 'com.srisarani.fotozenai/receipt_usb';
  static const _defaultInlinePayloadLimit = 65536;

  final MethodChannel _channel;
  final bool Function() _isAndroid;
  final int _inlinePayloadLimit;

  Future<bool> hasUsbHost() async {
    if (kIsWeb || !_isAndroid()) return false;
    try {
      return await _channel.invokeMethod<bool>('hasUsbHost') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// True when a USB Printer Class receipt device is visible (no connect yet).
  Future<bool> probeDevicePresent() async {
    if (kIsWeb || !_isAndroid()) return false;
    try {
      return await _channel.invokeMethod<bool>('probeDevice') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> ensureConnected() async {
    await _channel.invokeMethod<void>('requestPermission');
  }

  Future<void> sendEscPos(Uint8List bytes) async {
    if (bytes.length <= _inlinePayloadLimit) {
      await _channel.invokeMethod<void>(
        'sendEscPos',
        {'bytes': bytes},
      );
      return;
    }

    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'receipt_escpos_${DateTime.now().millisecondsSinceEpoch}.bin'));
    try {
      await file.writeAsBytes(bytes, flush: true);
      await _channel.invokeMethod<void>(
        'sendEscPosFile',
        {'filePath': file.path},
      );
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // ignore cleanup errors
      }
    }
  }
}
