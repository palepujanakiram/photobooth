import 'dart:math' as math;

import '../models/generation_timing_stats.dart';
import '../utils/app_strings.dart';

/// Phase of the portrait wait clock (drives copy and progress cap).
enum GenerationEtaPhase {
  starting,
  inProgress,
  polishing,
  longWait,
}

/// Presentation model for the portrait wait clock.
class GenerationEtaSnapshot {
  const GenerationEtaSnapshot({
    required this.phase,
    required this.primaryLine,
    required this.contextLine,
    required this.progressFraction,
    required this.estimatedTotalSeconds,
    required this.estimatedRemainingSeconds,
    this.showReassurance = false,
  });

  final GenerationEtaPhase phase;
  final String primaryLine;
  final String contextLine;
  final double progressFraction;
  final int estimatedTotalSeconds;
  final int estimatedRemainingSeconds;
  final bool showReassurance;
}

/// Formats seconds as `45 sec`, `1 min`, or `1:30`.
String formatGenerationEtaDuration(int seconds) {
  final s = seconds.clamp(0, 599);
  if (s < 60) return '$s sec';
  final m = s ~/ 60;
  final r = s % 60;
  if (r == 0) return '$m min';
  return '$m:${r.toString().padLeft(2, '0')}';
}

int _groupPhotoModifierSeconds(int? personCount) {
  final count = personCount != null && personCount > 0 ? personCount : 1;
  if (count > 2) return 20;
  if (count == 2) return 8;
  return 0;
}

int _baselineTotalSeconds(GenerationTimingStats stats, int? personCount) {
  final modifier = _groupPhotoModifierSeconds(personCount);
  if (stats.sampleCountLastHour >= 3) {
    return stats.lastHourAvgSeconds + modifier;
  }
  if (stats.sampleCountToday >= 5) {
    return stats.todayAvgSeconds + modifier;
  }
  if (stats.sampleCountWeek >= 3) {
    return stats.p50Seconds + modifier;
  }
  return GenerationTimingStats.defaults.p50Seconds + modifier;
}

/// Blends server timing stats, elapsed time, and pipeline stage into an ETA.
GenerationEtaSnapshot computeGenerationEta({
  required GenerationTimingStats stats,
  required int elapsedSeconds,
  required int? personCount,
  required bool hasAiPreview,
  required bool polishingStarted,
  required bool hasServerPreviews,
  required double pipelineProgress,
}) {
  final baseline = _baselineTotalSeconds(stats, personCount);
  final p90 = math.max(baseline + 30, stats.p90Seconds);
  var estimatedTotal = baseline;
  var remaining = math.max(15, estimatedTotal - elapsedSeconds);

  GenerationEtaPhase phase = GenerationEtaPhase.starting;
  var showReassurance = false;

  if (polishingStarted || (hasAiPreview && elapsedSeconds > baseline * 0.55)) {
    phase = GenerationEtaPhase.polishing;
    estimatedTotal = math.max(elapsedSeconds + 25, baseline);
    remaining = math.max(10, math.min(35, estimatedTotal - elapsedSeconds));
  } else if (hasServerPreviews || hasAiPreview) {
    phase = GenerationEtaPhase.inProgress;
    estimatedTotal = math.max(baseline, elapsedSeconds + math.max(30, remaining));
    remaining = math.max(15, estimatedTotal - elapsedSeconds);
  } else if (elapsedSeconds > p90) {
    phase = GenerationEtaPhase.longWait;
    estimatedTotal = elapsedSeconds + 45;
    remaining = 45;
    showReassurance = true;
  } else if (elapsedSeconds > 8) {
    phase = GenerationEtaPhase.inProgress;
  }

  if (elapsedSeconds > p90 && phase != GenerationEtaPhase.polishing) {
    phase = GenerationEtaPhase.longWait;
    remaining = math.max(30, p90 - elapsedSeconds + 30);
    showReassurance = true;
  }

  final primaryLine = _primaryLine(
    phase: phase,
    remainingSeconds: remaining,
    estimatedTotalSeconds: estimatedTotal,
    elapsedSeconds: elapsedSeconds,
  );

  final contextLine = _contextLine(stats: stats, phase: phase);

  final progress = _progressFraction(
    phase: phase,
    elapsedSeconds: elapsedSeconds,
    estimatedTotalSeconds: estimatedTotal,
    pipelineProgress: pipelineProgress,
    hasServerPreviews: hasServerPreviews,
  );

  return GenerationEtaSnapshot(
    phase: phase,
    primaryLine: primaryLine,
    contextLine: contextLine,
    progressFraction: progress,
    estimatedTotalSeconds: estimatedTotal,
    estimatedRemainingSeconds: remaining,
    showReassurance: showReassurance,
  );
}

String _primaryLine({
  required GenerationEtaPhase phase,
  required int remainingSeconds,
  required int estimatedTotalSeconds,
  required int elapsedSeconds,
}) {
  switch (phase) {
    case GenerationEtaPhase.polishing:
      return AppStrings.generationWaitEtaAlmostReady;
    case GenerationEtaPhase.longWait:
      return AppStrings.generationWaitEtaLongWait;
    case GenerationEtaPhase.starting:
      return AppStrings.generationWaitEtaAboutTotal(
        formatGenerationEtaDuration(estimatedTotalSeconds),
      );
    case GenerationEtaPhase.inProgress:
      if (elapsedSeconds < 12) {
        return AppStrings.generationWaitEtaAboutTotal(
          formatGenerationEtaDuration(estimatedTotalSeconds),
        );
      }
      return AppStrings.generationWaitEtaRemaining(
        formatGenerationEtaDuration(remainingSeconds),
      );
  }
}

String _contextLine({
  required GenerationTimingStats stats,
  required GenerationEtaPhase phase,
}) {
  if (stats.busy && phase != GenerationEtaPhase.polishing) {
    return AppStrings.generationWaitEtaBusy;
  }
  if (stats.sampleCountToday >= 3) {
    return AppStrings.generationWaitEtaTodayAvg(
      formatGenerationEtaDuration(stats.todayAvgSeconds),
    );
  }
  if (stats.sampleCountWeek >= 3) {
    return AppStrings.generationWaitEtaRecentAvg(
      formatGenerationEtaDuration(stats.p50Seconds),
    );
  }
  return AppStrings.generationWaitTimeExpectation;
}

double _progressFraction({
  required GenerationEtaPhase phase,
  required int elapsedSeconds,
  required int estimatedTotalSeconds,
  required double pipelineProgress,
  required bool hasServerPreviews,
}) {
  final cap = switch (phase) {
    GenerationEtaPhase.polishing => 0.95,
    GenerationEtaPhase.longWait => 0.92,
    _ => 0.88,
  };

  final elapsedFrac = estimatedTotalSeconds > 0
      ? (elapsedSeconds / estimatedTotalSeconds).clamp(0.0, cap)
      : 0.0;

  var blended = elapsedFrac;
  if (hasServerPreviews && pipelineProgress > 0.08) {
    blended = math.max(elapsedFrac, pipelineProgress.clamp(0.0, cap));
  } else if (!hasServerPreviews && elapsedSeconds > 0) {
    blended = math.min(cap * 0.35, elapsedSeconds / 45.0 * 0.28);
  }

  return blended.clamp(0.04, cap);
}
