import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android native USB channel for DNP DS-RX1(S)HS.
class DnpUsbClient {
  DnpUsbClient({
    MethodChannel? channel,
    bool Function()? isAndroid,
  })  : _channel = channel ?? const MethodChannel(_channelName),
        _isAndroid = isAndroid ?? (() => !kIsWeb && Platform.isAndroid);

  static const _channelName = 'com.srisarani.fotozenai/dnp_usb';

  final MethodChannel _channel;
  final bool Function() _isAndroid;

  Future<bool> hasUsbHost() async {
    if (kIsWeb || !_isAndroid()) return false;
    try {
      return await _channel.invokeMethod<bool>('hasUsbHost') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> ensureConnected() async {
    await _channel.invokeMethod<void>('requestPermission');
  }

  Future<void> print({
    required String filePath,
    required String paperSize,
    required int copies,
  }) async {
    await _channel.invokeMethod<void>(
      'print',
      {
        'filePath': filePath,
        'paperSize': paperSize,
        'copies': copies,
      },
    );
  }
}
