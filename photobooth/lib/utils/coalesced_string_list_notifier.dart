import 'package:flutter/foundation.dart' show ValueNotifier, kIsWeb;
import 'package:flutter/scheduler.dart';

/// Batches rapid list appends so debug HUD [ValueNotifier]s do not repaint on
/// every log line during capture/upload (web main-thread starvation).
class CoalescedStringListNotifier {
  CoalescedStringListNotifier({required this.maxLines});

  final int maxLines;
  final ValueNotifier<List<String>> lines = ValueNotifier<List<String>>([]);

  final List<String> _pending = <String>[];
  bool _flushScheduled = false;

  void appendAll(Iterable<String> newLines) {
    _pending.addAll(newLines);
    _scheduleFlush();
  }

  void clear() {
    _pending.clear();
    lines.value = <String>[];
  }

  void _scheduleFlush() {
    if (!kIsWeb) {
      _flush();
      return;
    }
    if (_flushScheduled) return;
    _flushScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _flushScheduled = false;
      _flush();
    });
  }

  void _flush() {
    if (_pending.isEmpty) return;
    final current = lines.value;
    final next = <String>[...current, ..._pending];
    _pending.clear();
    lines.value =
        next.length > maxLines ? next.sublist(next.length - maxLines) : next;
  }
}
