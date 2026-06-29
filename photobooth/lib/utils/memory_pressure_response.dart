import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart';

import '../services/file_helper.dart';
import 'logger.dart';

/// Drops decoded images that no longer have listeners (safe mid-session).
void trimFlutterMemoryCaches() {
  if (kIsWeb) return;
  final ic = PaintingBinding.instance.imageCache;
  ic.clearLiveImages();
}

/// Best-effort RAM relief when the OS reports memory pressure.
void respondToAppMemoryPressure() {
  if (kIsWeb) return;
  trimFlutterMemoryCaches();
  unawaited(
    FileHelper.cleanupTempImages().catchError((Object e, StackTrace st) {
      AppLogger.debug('Memory pressure temp cleanup failed: $e');
    }),
  );
}
