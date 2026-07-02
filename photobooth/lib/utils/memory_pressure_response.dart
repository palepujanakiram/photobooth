import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart';

/// Drops decoded images that no longer have listeners (safe mid-session).
void trimFlutterMemoryCaches({bool aggressive = false}) {
  if (kIsWeb) return;
  final ic = PaintingBinding.instance.imageCache;
  ic.clearLiveImages();
  if (aggressive) {
    ic.clear();
  }
}

/// Best-effort RAM relief when the OS reports memory pressure or RSS is high.
///
/// Trims Flutter's decoded [ImageCache] only. Temp image files on disk are left
/// intact so Pay & Collect can still print after payment (those paths use
/// `transformed_*` under the app temp dir). Temp cleanup runs at session end
/// via [FileHelper.cleanupTempImages] in lifecycle/privacy flows.
void respondToAppMemoryPressure() {
  if (kIsWeb) return;
  trimFlutterMemoryCaches(aggressive: true);
}
