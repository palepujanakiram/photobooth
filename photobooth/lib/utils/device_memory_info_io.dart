import 'package:flutter/services.dart';

import '../models/device_memory_snapshot.dart';
import 'process_rss_io.dart';

const _channel = MethodChannel('photobooth/device_memory');

Future<DeviceMemorySnapshot> readDeviceMemorySnapshot() async {
  final processRssBytes = currentProcessResidentBytes();
  try {
    final raw = await _channel.invokeMethod<Object>('getMemoryInfo');
    if (raw is Map) {
      return DeviceMemorySnapshot(
        processRssBytes: processRssBytes ?? _asInt(raw['processRssBytes']),
        availableSystemBytes: _asInt(raw['availableBytes']),
        totalSystemBytes: _asInt(raw['totalBytes']),
        systemLowMemoryFlag: raw['lowMemory'] == true,
      );
    }
  } on MissingPluginException {
    // Unit tests / platforms without native handler.
  } on PlatformException {
    // Best-effort; fall back to RSS-only snapshot below.
  }
  return DeviceMemorySnapshot(processRssBytes: processRssBytes);
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}
