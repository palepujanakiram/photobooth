import 'dart:async';

import '../models/parallel_generation_result.dart';
import '../utils/exceptions.dart';
import 'api_image_url_utils.dart';

/// Handles one SSE event type from parallel generation (extracted from [api_sse_dispatch.dart]).
void handleParallelSseEvent(
  String eventType,
  Map<String, dynamic> json, {
  required List<String> slots,
  required Map<int, double> qualityByIndex,
  required Completer<ParallelGenerationResult> completer,
  void Function(String message)? onProgress,
}) {
  switch (eventType) {
    case 'status':
      _onStatus(json, onProgress);
    case 'start':
      _onStart(json, onProgress);
    case 'step':
      _onStep(json, onProgress);
    case 'attempt_start':
      _onAttemptStart(json, onProgress);
    case 'attempt_complete':
      _onAttemptComplete(json, onProgress);
    case 'commentary':
      _onCommentary(json, onProgress);
    case 'commentary_clear':
      break;
    case 'warning':
      _onWarning(json, onProgress);
    case 'image_complete':
      _onImageComplete(json, slots, qualityByIndex, onProgress);
    case 'image_failed':
      onProgress?.call('One option failed, continuing...');
    case 'complete':
      _onComplete(json, slots, qualityByIndex, completer);
    case 'failure':
    case 'error':
      _onFailure(json, completer);
    default:
      break;
  }
}

void _onStatus(Map<String, dynamic> json, void Function(String message)? onProgress) {
  final total = json['imageCount'] ?? json['total'];
  onProgress?.call(
    total != null
        ? 'Starting generation ($total options)...'
        : 'Starting generation...',
  );
}

void _onStart(Map<String, dynamic> json, void Function(String message)? onProgress) {
  final total = json['total'];
  onProgress?.call(
    total != null
        ? 'Starting parallel generation ($total options)...'
        : 'Starting parallel generation...',
  );
}

void _onStep(Map<String, dynamic> json, void Function(String message)? onProgress) {
  final step = json['step'] as String?;
  final st = json['status'] as String?;
  if (step != null && st == 'active') {
    onProgress?.call('Step: $step');
  }
}

void _onAttemptStart(
  Map<String, dynamic> json,
  void Function(String message)? onProgress,
) {
  final a = json['attempt'];
  final ta = json['totalAttempts'];
  if (a != null && ta != null) {
    onProgress?.call('Attempt $a of $ta...');
  }
}

void _onAttemptComplete(
  Map<String, dynamic> json,
  void Function(String message)? onProgress,
) {
  final sc = json['score'];
  if (sc != null) {
    onProgress?.call('Quality score: $sc');
  }
}

void _onCommentary(
  Map<String, dynamic> json,
  void Function(String message)? onProgress,
) {
  final m = json['message'] as String?;
  if (m != null && m.isNotEmpty) {
    onProgress?.call(m);
  }
}

void _onWarning(
  Map<String, dynamic> json,
  void Function(String message)? onProgress,
) {
  final w = json['message'] as String?;
  if (w != null && w.isNotEmpty) {
    onProgress?.call('Warning: $w');
  }
}

void _onImageComplete(
  Map<String, dynamic> json,
  List<String> slots,
  Map<int, double> qualityByIndex,
  void Function(String message)? onProgress,
) {
  final idx = _parseIndex(json['index']);
  final url = json['imageUrl'] as String?;
  final q = json['qualityScore'];
  if (idx == null ||
      idx < 0 ||
      idx >= slots.length ||
      url == null ||
      url.isEmpty) {
    return;
  }
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

void _onComplete(
  Map<String, dynamic> json,
  List<String> slots,
  Map<int, double> qualityByIndex,
  Completer<ParallelGenerationResult> completer,
) {
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
  final totalMs = _parseInt(timing?['totalMs']);
  final runId = json['runId'] as String?;
  final selectedIndex = _parseIndex(json['selectedIndex']);
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
}

void _onFailure(
  Map<String, dynamic> json,
  Completer<ParallelGenerationResult> completer,
) {
  final msg = json['error'] as String? ??
      json['message'] as String? ??
      'Generation failed';
  if (!completer.isCompleted) {
    completer.completeError(ApiException(msg));
  }
}

int? _parseIndex(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return null;
}

int? _parseInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return null;
}
