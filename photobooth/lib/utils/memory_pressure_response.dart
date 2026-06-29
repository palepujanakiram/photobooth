import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/painting.dart';

import '../services/file_helper.dart';
import 'logger.dart';

/// Test hook for [respondToAppMemoryPressure] temp cleanup.
@visibleForTesting
Future<void> Function() memoryPressureTempCleanup = FileHelper.cleanupTempImages;

/// Drops decoded images that no longer have listeners (safe mid-session).
void trimFlutterMemoryCaches({bool aggressive = false}) {
  if (kIsWeb) return;
  final ic = PaintingBinding.instance.imageCache;
  ic.clearLiveImages();
  if (aggressive) {
    ic.clear();
  }
}

/// Best-effort RAM relief when the OS reports memory pressure.
void respondToAppMemoryPressure() {
  if (kIsWeb) return;
  trimFlutterMemoryCaches(aggressive: true);
  unawaited(
    memoryPressureTempCleanup().catchError((Object e, StackTrace st) {
      AppLogger.debug('Memory pressure temp cleanup failed: $e');
    }),
  );
}
