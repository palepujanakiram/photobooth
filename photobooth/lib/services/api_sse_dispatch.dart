import 'dart:async';
import 'dart:convert';

import '../models/parallel_generation_result.dart';
import 'api_sse_event_handlers.dart';

/// Parses one SSE block from parallel generation stream.
void dispatchParallelSseBlock(
  String block, {
  required List<String> slots,
  required Map<int, double> qualityByIndex,
  required Completer<ParallelGenerationResult> completer,
  void Function(String message)? onProgress,
  void Function(String eventType, Map<String, dynamic> json)? onSseEvent,
}) {
  String? eventType;
  final dataParts = <String>[];
  for (final rawLine in block.split('\n')) {
    final line = rawLine.trimRight();
    if (line.isEmpty) continue;
    if (line.startsWith('event:')) {
      eventType = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      dataParts.add(line.substring(5).trimLeft());
    }
  }
  if (dataParts.isEmpty) return;

  final payload = dataParts.join('\n');
  final Map<String, dynamic> json;
  try {
    json = jsonDecode(payload) as Map<String, dynamic>;
  } catch (_) {
    return;
  }

  final et = (eventType ?? '').trim();
  if (et.isNotEmpty) {
    onSseEvent?.call(et, json);
    handleParallelSseEvent(
      et,
      json,
      slots: slots,
      qualityByIndex: qualityByIndex,
      completer: completer,
      onProgress: onProgress,
    );
  }
}
