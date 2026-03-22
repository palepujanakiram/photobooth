/// Result of [ApiService.generateImageParallelStream] (SSE parallel generation).
class ParallelGenerationResult {
  ParallelGenerationResult({
    required this.imageUrlsBySlot,
    this.success = true,
    this.timingTotalMs,
    Map<int, double>? qualityScoreByIndex,
  }) : qualityScoreByIndex = qualityScoreByIndex ?? const {};

  /// One entry per requested slot; empty string means that slot failed or was omitted.
  final List<String> imageUrlsBySlot;
  final bool success;
  final int? timingTotalMs;
  final Map<int, double> qualityScoreByIndex;

  String? get firstImageUrl {
    for (final u in imageUrlsBySlot) {
      if (u.isNotEmpty) return u;
    }
    return null;
  }

  /// Prefer the slot with the highest [qualityScoreByIndex] when present.
  String? get preferredImageUrl {
    if (qualityScoreByIndex.isEmpty) return firstImageUrl;
    final entries = qualityScoreByIndex.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in entries) {
      final i = e.key;
      if (i >= 0 && i < imageUrlsBySlot.length) {
        final u = imageUrlsBySlot[i];
        if (u.isNotEmpty) return u;
      }
    }
    return firstImageUrl;
  }
}
