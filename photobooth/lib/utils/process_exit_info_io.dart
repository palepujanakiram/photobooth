import 'package:flutter/services.dart';

import '../models/android_process_exit.dart';

const _channel = MethodChannel('photobooth/process_exits');

Future<List<AndroidProcessExit>> readHistoricalProcessExits() async {
  try {
    final raw = await _channel.invokeMethod<Object>('getHistoricalProcessExits');
    return AndroidProcessExit.parseList(raw);
  } on MissingPluginException {
    return const [];
  } on PlatformException {
    return const [];
  }
}
