import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/parallel_generation_result.dart';
import '../utils/exceptions.dart';
import 'api_sse_dispatch.dart';

/// Reads an SSE [ResponseBody] stream into [ParallelGenerationResult].
Future<ParallelGenerationResult> consumeParallelGenerationSseStream(
  ResponseBody body, {
  required int slotCount,
  void Function(String message)? onProgress,
  void Function(String eventType, Map<String, dynamic> json)? onSseEvent,
}) async {
  final slots = List<String>.filled(slotCount, '');
  final qualityByIndex = <int, double>{};
  final completer = Completer<ParallelGenerationResult>();
  final buffer = StringBuffer();

  final dispatchArgs = _ParallelSseDispatchArgs(
    slots: slots,
    qualityByIndex: qualityByIndex,
    completer: completer,
    onProgress: onProgress,
    onSseEvent: onSseEvent,
  );

  try {
    await for (final chunk in utf8.decoder.bind(body.stream)) {
      buffer.write(chunk);
      while (_drainNextSseBlock(buffer, dispatchArgs)) {
        if (completer.isCompleted) {
          return await completer.future;
        }
      }
    }
    _dispatchTrailingSseBuffer(buffer, dispatchArgs);
  } catch (e) {
    _completeParallelSseStreamError(completer, e);
  }

  _completeParallelSseStreamIfNeeded(completer, slots, qualityByIndex);
  return completer.future;
}

class _ParallelSseDispatchArgs {
  _ParallelSseDispatchArgs({
    required this.slots,
    required this.qualityByIndex,
    required this.completer,
    this.onProgress,
    this.onSseEvent,
  });

  final List<String> slots;
  final Map<int, double> qualityByIndex;
  final Completer<ParallelGenerationResult> completer;
  final void Function(String message)? onProgress;
  final void Function(String eventType, Map<String, dynamic> json)? onSseEvent;
}

bool _drainNextSseBlock(
  StringBuffer buffer,
  _ParallelSseDispatchArgs args,
) {
  final current = buffer.toString();
  final sep = current.indexOf('\n\n');
  if (sep < 0) return false;

  var block = current.substring(0, sep);
  final remaining = current.substring(sep + 2);
  buffer
    ..clear()
    ..write(remaining);
  if (block.endsWith('\r')) {
    block = block.substring(0, block.length - 1);
  }
  dispatchParallelSseBlock(
    block,
    slots: args.slots,
    qualityByIndex: args.qualityByIndex,
    completer: args.completer,
    onProgress: args.onProgress,
    onSseEvent: args.onSseEvent,
  );
  return true;
}

void _dispatchTrailingSseBuffer(
  StringBuffer buffer,
  _ParallelSseDispatchArgs args,
) {
  final remaining = buffer.toString();
  if (remaining.trim().isEmpty) return;
  dispatchParallelSseBlock(
    remaining,
    slots: args.slots,
    qualityByIndex: args.qualityByIndex,
    completer: args.completer,
    onProgress: args.onProgress,
    onSseEvent: args.onSseEvent,
  );
}

void _completeParallelSseStreamError(
  Completer<ParallelGenerationResult> completer,
  Object e,
) {
  if (!completer.isCompleted) {
    completer.completeError(
      ApiException('Parallel generation stream failed: $e'),
    );
  }
}

void _completeParallelSseStreamIfNeeded(
  Completer<ParallelGenerationResult> completer,
  List<String> slots,
  Map<int, double> qualityByIndex,
) {
  if (completer.isCompleted) return;
  if (slots.any((u) => u.isNotEmpty)) {
    completer.complete(
      ParallelGenerationResult(
        imageUrlsBySlot: List<String>.from(slots),
        success: true,
        qualityScoreByIndex: Map<int, double>.from(qualityByIndex),
      ),
    );
    return;
  }
  completer.completeError(
    ApiException('Generation ended without any image'),
  );
}
