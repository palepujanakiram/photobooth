/// Extracts transformation run ids from session / runs API payloads.
String? transformationRunIdFromSessionMap(Map<String, dynamic>? map) {
  if (map == null) return null;
  for (final key in const [
    'activeTransformationRunId',
    'active_transformation_run_id',
    'runId',
    'run_id',
  ]) {
    final raw = map[key]?.toString().trim();
    if (raw != null && raw.isNotEmpty) return raw;
  }
  final nested = map['session'];
  if (nested is Map) {
    return transformationRunIdFromSessionMap(
      Map<String, dynamic>.from(nested),
    );
  }
  return null;
}

/// Latest run id from `GET /api/sessions/:id/runs` (`{ runs: [...] }`).
String? latestTransformationRunIdFromRunsResponse(
  Map<String, dynamic>? payload,
) {
  if (payload == null) return null;
  final runs = payload['runs'];
  if (runs is! List || runs.isEmpty) return null;

  String? idOf(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString().trim();
    return (id != null && id.isNotEmpty) ? id : null;
  }

  for (var i = runs.length - 1; i >= 0; i--) {
    final id = idOf(runs[i]);
    if (id != null) return id;
  }
  return null;
}
