import 'dart:html' as html;

/// Chrome / Edge: `performance.memory.usedJSHeapSize` (not in Firefox/Safari).
int? currentProcessResidentBytes() {
  try {
    return html.window.performance.memory?.usedJSHeapSize;
  } catch (_) {
    return null;
  }
}
