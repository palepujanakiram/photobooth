import 'dart:async';
import 'dart:convert';

import '../models/parallel_generation_result.dart';
import '../utils/exceptions.dart';
import 'api_image_url_utils.dart';

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
  }

  switch (et) {
    case 'status':
      final total = json['imageCount'] ?? json['total'];
      onProgress?.call(
        total != null
            ? 'Starting generation ($total options)...'
            : 'Starting generation...',
      );
      break;
    case 'start':
      final total = json['total'];
      onProgress?.call(
        total != null
            ? 'Starting parallel generation ($total options)...'
            : 'Starting parallel generation...',
      );
      break;
    case 'step':
      final step = json['step'] as String?;
      final st = json['status'] as String?;
      if (step != null && st == 'active') {
        onProgress?.call('Step: $step');
      }
      break;
    case 'attempt_start':
      final a = json['attempt'];
      final ta = json['totalAttempts'];
      if (a != null && ta != null) {
        onProgress?.call('Attempt $a of $ta...');
      }
      break;
    case 'attempt_complete':
      final sc = json['score'];
      if (sc != null) {
        onProgress?.call('Quality score: $sc');
      }
      break;
    case 'commentary':
      final m = json['message'] as String?;
      if (m != null && m.isNotEmpty) {
        onProgress?.call(m);
      }
      break;
    case 'commentary_clear':
      break;
    case 'warning':
      final w = json['message'] as String?;
      if (w != null && w.isNotEmpty) {
        onProgress?.call('Warning: $w');
      }
      break;
    case 'image_complete':
      int? idx;
      final rawIdx = json['index'];
      if (rawIdx is int) {
        idx = rawIdx;
      } else if (rawIdx is num) {
        idx = rawIdx.toInt();
      }
      final url = json['imageUrl'] as String?;
      final q = json['qualityScore'];
      if (idx != null &&
          idx >= 0 &&
          idx < slots.length &&
          url != null &&
          url.isNotEmpty) {
        slots[idx] = resolveApiImageUrl(url);
        if (q is num) {
          qualityByIndex[idx] = q.toDouble();
        }
        final c = json['completed'];
        final t = json['total'];
        if (c != null && t != null) {
          onProgress?.call('Option $c of $t ready...');
        } else {
          onProgress?.call('An option finished...');
        }
      }
      break;
    case 'image_failed':
      onProgress?.call('One option failed, continuing...');
      break;
    case 'complete':
      final urls = json['imageUrls'];
      if (urls is List) {
        for (var i = 0; i < urls.length && i < slots.length; i++) {
          final u = urls[i];
          if (u is String && u.isNotEmpty) {
            slots[i] = resolveApiImageUrl(u);
          }
        }
      }
      final timing = json['timing'] as Map<String, dynamic>?;
      int? totalMs;
      final rawMs = timing?['totalMs'];
      if (rawMs is int) {
        totalMs = rawMs;
      } else if (rawMs is num) {
        totalMs = rawMs.toInt();
      }
      final runId = json['runId'] as String?;
      final selRaw = json['selectedIndex'];
      int? selectedIndex;
      if (selRaw is int) {
        selectedIndex = selRaw;
      } else if (selRaw is num) {
        selectedIndex = selRaw.toInt();
      }
      if (!completer.isCompleted) {
        completer.complete(
          ParallelGenerationResult(
            imageUrlsBySlot: List<String>.from(slots),
            success: json['success'] == true,
            timingTotalMs: totalMs,
            qualityScoreByIndex: Map<int, double>.from(qualityByIndex),
            runId: runId,
            selectedIndex: selectedIndex,
          ),
        );
      }
      break;
    case 'failure':
    case 'error':
      final msg = json['error'] as String? ??
          json['message'] as String? ??
          'Generation failed';
      if (!completer.isCompleted) {
        completer.completeError(ApiException(msg));
      }
      break;
    default:
      break;
  }
}
