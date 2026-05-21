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

  try {
    await for (final chunk in utf8.decoder.bind(body.stream)) {
      buffer.write(chunk);
      while (true) {
        final current = buffer.toString();
        final sep = current.indexOf('\n\n');
        if (sep < 0) break;
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
          slots: slots,
          qualityByIndex: qualityByIndex,
          completer: completer,
          onProgress: onProgress,
          onSseEvent: onSseEvent,
        );
        if (completer.isCompleted) {
          return completer.future;
        }
      }
    }
    final remaining = buffer.toString();
    if (remaining.trim().isNotEmpty) {
      dispatchParallelSseBlock(
        remaining,
        slots: slots,
        qualityByIndex: qualityByIndex,
        completer: completer,
        onProgress: onProgress,
        onSseEvent: onSseEvent,
      );
    }
  } catch (e) {
    if (!completer.isCompleted) {
      completer.completeError(
        ApiException('Parallel generation stream failed: $e'),
      );
    }
  }

  if (!completer.isCompleted) {
    if (slots.any((u) => u.isNotEmpty)) {
      completer.complete(
        ParallelGenerationResult(
          imageUrlsBySlot: List<String>.from(slots),
          success: true,
          qualityScoreByIndex: Map<int, double>.from(qualityByIndex),
        ),
      );
    } else {
      completer.completeError(
        ApiException('Generation ended without any image'),
      );
    }
  }

  return completer.future;
}
