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
