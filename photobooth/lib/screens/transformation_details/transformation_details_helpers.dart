import 'dart:convert';

/// Parsing helpers for transformation details API payload (Sonar S3776).
List<Map<String, dynamic>> parseTransformationSteps(dynamic stepsRaw) {
  if (stepsRaw is! List) return <Map<String, dynamic>>[];
  final steps = stepsRaw
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  steps.sort(_compareStepStartTimes);
  return steps;
}

int _compareStepStartTimes(Map<String, dynamic> a, Map<String, dynamic> b) {
  final ta = _parseStepTime(a['startedAt']);
  final tb = _parseStepTime(b['startedAt']);
  if (ta == null && tb == null) return 0;
  if (ta == null) return 1;
  if (tb == null) return -1;
  return ta.compareTo(tb);
}

DateTime? _parseStepTime(dynamic v) {
  if (v is String && v.trim().isNotEmpty) {
    return DateTime.tryParse(v.trim());
  }
  return null;
}

Map<String, dynamic> parseRunMetadata(Map<String, dynamic> run) {
  if (run['metadata'] is Map) {
    return Map<String, dynamic>.from(run['metadata'] as Map);
  }
  return <String, dynamic>{};
}

Map<String, dynamic> parseAppliedSettings(Map<String, dynamic> meta) {
  if (meta['appliedSettings'] is Map) {
    return Map<String, dynamic>.from(meta['appliedSettings'] as Map);
  }
  return <String, dynamic>{};
}

Map<String, dynamic>? _mapOrNull(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return null;
}

bool _looksLikeIdentityVerification(Map<String, dynamic> data) {
  if (data.containsKey('passed') &&
      (_identityField(data, [
            'embeddingMinSimilarity',
            'minFaceScore',
            'embeddingAvgSimilarity',
            'avgFaceScore',
          ]) !=
          null)) {
    return true;
  }
  return _identityField(data, [
        'embeddingMinSimilarity',
        'embeddingAvgSimilarity',
        'embeddingThresholdUsed',
      ]) !=
      null;
}

Map<String, dynamic>? _identityFromMap(dynamic value) {
  if (value is String && value.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return null;
    }
  }
  final map = _mapOrNull(value);
  if (map != null && _looksLikeIdentityVerification(map)) {
    return map;
  }
  if (map != null) {
    final nested = _mapOrNull(map['identityVerification']) ??
        _mapOrNull(map['identity_verification']);
    if (nested != null) return nested;
  }
  return null;
}

Map<String, dynamic>? _identityFromStep(Map<String, dynamic> step) {
  for (final key in ['metadata', 'outputData', 'inputData']) {
    final found = _identityFromMap(step[key]);
    if (found != null) return found;
  }
  return null;
}

/// Identity verification block from generation run API (`identity_verification` JSON).
Map<String, dynamic>? parseIdentityVerification({
  required Map<String, dynamic> payload,
  required Map<String, dynamic> run,
  required List<Map<String, dynamic>> steps,
}) {
  for (final source in [
    payload,
    run,
    parseRunMetadata(run),
    payload['generationLog'],
    payload['generation_log'],
    payload['log'],
  ]) {
    final found = _identityFromMap(source);
    if (found != null) return found;
  }

  for (final step in steps) {
    final found = _identityFromStep(step);
    if (found != null) return found;
  }

  return null;
}

dynamic _identityField(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    if (data.containsKey(key)) return data[key];
  }
  return null;
}

String formatIdentityVerificationScore(dynamic value) {
  if (value is! num) return value?.toString() ?? '—';
  if (value > 0 && value <= 1) {
    return '${(value * 100).round()}%';
  }
  return '${value.round()}%';
}

/// Human-readable lines for the transformation details identity card.
///
/// Supports backend shapes:
/// - `minFaceScore` / `avgFaceScore` / `thresholdUsed` / `failedFaceIndices`
/// - `embeddingMinSimilarity` / `embeddingAvgSimilarity` / `embeddingThresholdUsed` /
///   `embeddingFailedFaceIndices` (0–100 scale)
List<String> identityVerificationSummaryLines(Map<String, dynamic> data) {
  final lines = <String>[];
  final passed = data['passed'];
  if (passed is bool) {
    lines.add('Result: ${passed ? 'Passed' : 'Failed'}');
  }
  final personCountMatch = _identityField(data, ['personCountMatch']);
  if (personCountMatch is bool) {
    lines.add('Face count match: ${personCountMatch ? 'Yes' : 'No'}');
  }
  final threshold = _identityField(data, [
    'thresholdUsed',
    'embeddingThresholdUsed',
  ]);
  if (threshold != null) {
    lines.add('Threshold: ${formatIdentityVerificationScore(threshold)}');
  }
  final minScore = _identityField(data, [
    'minFaceScore',
    'embeddingMinSimilarity',
  ]);
  if (minScore != null) {
    lines.add('Min face score: ${formatIdentityVerificationScore(minScore)}');
  }
  final avgScore = _identityField(data, [
    'avgFaceScore',
    'embeddingAvgSimilarity',
  ]);
  if (avgScore != null) {
    lines.add('Avg face score: ${formatIdentityVerificationScore(avgScore)}');
  }
  final perFace = _identityField(data, [
    'perFaceScores',
    'embeddingPerFaceSimilarities',
  ]);
  if (perFace is List && perFace.isNotEmpty) {
    final formatted = perFace
        .map(formatIdentityVerificationScore)
        .join(', ');
    lines.add('Per-face scores: $formatted');
  }
  final failed = _identityField(data, [
    'failedFaceIndices',
    'embeddingFailedFaceIndices',
  ]);
  if (failed is List && failed.isNotEmpty) {
    lines.add('Failed face indices: ${failed.join(', ')}');
  }
  final retryCount = data['retryCount'];
  if (retryCount is num) {
    lines.add('Retries: ${retryCount.round()}');
  }
  final themeName = data['themeName']?.toString();
  if (themeName != null && themeName.isNotEmpty) {
    lines.add('Theme: $themeName');
  } else {
    final themeId = data['themeId']?.toString();
    if (themeId != null && themeId.isNotEmpty) {
      lines.add('Theme ID: $themeId');
    }
  }
  final snippet = data['promptSnippet']?.toString();
  if (snippet != null && snippet.isNotEmpty) {
    final trimmed =
        snippet.length > 120 ? '${snippet.substring(0, 120)}…' : snippet;
    lines.add('Prompt snippet: $trimmed');
  }
  return lines;
}

String? finalPromptFromAiStep(Map<String, dynamic>? aiStep) {
  if (aiStep == null) return null;
  final out = aiStep['outputData'];
  final m = aiStep['metadata'];
  if (out is Map && out['finalPrompt'] != null) {
    return out['finalPrompt'].toString();
  }
  if (m is Map && m['finalPrompt'] != null) {
    return m['finalPrompt'].toString();
  }
  return null;
}

Map<String, dynamic>? findAiGenerationStep(List<Map<String, dynamic>> steps) {
  for (final s in steps) {
    final stage = s['stage']?.toString() ?? '';
    if (stage == 'ai_generation' || stage == 'ai') return s;
  }
  return null;
}

/// Session id from `run.sessionId` (authoritative for log correlation).
String? sessionIdFromRun(Map<String, dynamic> run) {
  final id = run['sessionId']?.toString().trim();
  if (id == null || id.isEmpty) return null;
  return id;
}

/// Run id from `run.id` / `run.runId`.
String? runIdFromRun(Map<String, dynamic> run) {
  for (final key in ['id', 'runId']) {
    final id = run[key]?.toString().trim();
    if (id != null && id.isNotEmpty) return id;
  }
  return null;
}

String formatClientDisplayElapsed(int? elapsedSeconds) {
  if (elapsedSeconds == null || elapsedSeconds < 0) return '—';
  return '${elapsedSeconds}s';
}

String formatServerDurationMs(dynamic durationMs) {
  if (durationMs is! num) return '—';
  return '${durationMs.round()} ms';
}

/// One-line bundle for pasting into backend / Fly logs.
String buildTransformationLogClipboardText({
  required String? sessionId,
  required String? runId,
  int? clientDisplayElapsedSeconds,
  dynamic serverDurationMs,
}) {
  final parts = <String>[
    if (sessionId != null && sessionId.isNotEmpty) 'sessionId=$sessionId',
    if (runId != null && runId.isNotEmpty) 'runId=$runId',
    if (clientDisplayElapsedSeconds != null && clientDisplayElapsedSeconds >= 0)
      'displaySeconds=$clientDisplayElapsedSeconds',
    if (serverDurationMs is num) 'serverDurationMs=${serverDurationMs.round()}',
  ];
  return parts.join(' ');
}
