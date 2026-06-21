import 'package:web/web.dart' as web;

/// Chrome / Edge: `performance.memory.usedJSHeapSize` (not in Firefox/Safari).
int? currentProcessResidentBytes() {
  try {
    // ignore: avoid_dynamic_calls
    final memory = (web.window.performance as dynamic).memory;
    if (memory == null) return null;
    // ignore: avoid_dynamic_calls
    final bytes = memory.usedJSHeapSize as num?;
    return bytes?.toInt();
  } catch (_) {
    return null;
  }
}
