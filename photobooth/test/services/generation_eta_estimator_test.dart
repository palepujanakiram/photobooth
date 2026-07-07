import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/generation_timing_stats.dart';
import 'package:photobooth/services/generation_eta_estimator.dart';
import 'package:photobooth/utils/app_strings.dart';

void main() {
  group('formatGenerationEtaDuration', () {
    test('formats seconds and minutes', () {
      expect(formatGenerationEtaDuration(45), '45 sec');
      expect(formatGenerationEtaDuration(60), '1 min');
      expect(formatGenerationEtaDuration(90), '1:30');
    });
  });

  group('computeGenerationEta', () {
    const stats = GenerationTimingStats(
      p50Seconds: 80,
      p90Seconds: 140,
      lastHourAvgSeconds: 95,
      todayAvgSeconds: 88,
      sampleCountLastHour: 8,
      sampleCountToday: 20,
      sampleCountWeek: 50,
      busy: false,
    );

    test('starting phase uses about-total copy', () {
      final eta = computeGenerationEta(
        stats: stats,
        elapsedSeconds: 3,
        personCount: 1,
        hasAiPreview: false,
        polishingStarted: false,
        hasServerPreviews: false,
        pipelineProgress: 0,
      );
      expect(eta.phase, GenerationEtaPhase.starting);
      expect(eta.primaryLine, contains('About'));
      expect(eta.contextLine, AppStrings.generationWaitEtaTodayAvg('1:28'));
    });

    test('in-progress shows remaining after warmup', () {
      final eta = computeGenerationEta(
        stats: stats,
        elapsedSeconds: 40,
        personCount: 1,
        hasAiPreview: false,
        polishingStarted: false,
        hasServerPreviews: true,
        pipelineProgress: 0.35,
      );
      expect(eta.phase, GenerationEtaPhase.inProgress);
      expect(eta.primaryLine, contains('remaining'));
      expect(eta.progressFraction, greaterThan(0.2));
    });

    test('polishing tightens remaining time', () {
      final eta = computeGenerationEta(
        stats: stats,
        elapsedSeconds: 100,
        personCount: 1,
        hasAiPreview: true,
        polishingStarted: true,
        hasServerPreviews: true,
        pipelineProgress: 0.7,
      );
      expect(eta.phase, GenerationEtaPhase.polishing);
      expect(eta.primaryLine, AppStrings.generationWaitEtaAlmostReady);
      expect(eta.estimatedRemainingSeconds, lessThanOrEqualTo(35));
    });

    test('long wait when elapsed exceeds p90', () {
      final eta = computeGenerationEta(
        stats: stats,
        elapsedSeconds: 160,
        personCount: 1,
        hasAiPreview: false,
        polishingStarted: false,
        hasServerPreviews: false,
        pipelineProgress: 0.1,
      );
      expect(eta.phase, GenerationEtaPhase.longWait);
      expect(eta.showReassurance, isTrue);
      expect(eta.primaryLine, AppStrings.generationWaitEtaLongWait);
    });

    test('busy kiosk shows busy context', () {
      const busyStats = GenerationTimingStats(
        p50Seconds: 80,
        p90Seconds: 140,
        lastHourAvgSeconds: 120,
        todayAvgSeconds: 88,
        sampleCountLastHour: 6,
        sampleCountToday: 20,
        sampleCountWeek: 50,
        busy: true,
      );
      final eta = computeGenerationEta(
        stats: busyStats,
        elapsedSeconds: 20,
        personCount: 1,
        hasAiPreview: false,
        polishingStarted: false,
        hasServerPreviews: false,
        pipelineProgress: 0,
      );
      expect(eta.contextLine, AppStrings.generationWaitEtaBusy);
    });

    test('group photos add baseline time', () {
      final solo = computeGenerationEta(
        stats: stats,
        elapsedSeconds: 0,
        personCount: 1,
        hasAiPreview: false,
        polishingStarted: false,
        hasServerPreviews: false,
        pipelineProgress: 0,
      );
      final group = computeGenerationEta(
        stats: stats,
        elapsedSeconds: 0,
        personCount: 4,
        hasAiPreview: false,
        polishingStarted: false,
        hasServerPreviews: false,
        pipelineProgress: 0,
      );
      expect(
        group.estimatedTotalSeconds,
        greaterThan(solo.estimatedTotalSeconds),
      );
    });

    test('couple photos add smaller baseline modifier', () {
      const coupleStats = GenerationTimingStats(
        p50Seconds: 80,
        p90Seconds: 140,
        lastHourAvgSeconds: 95,
        todayAvgSeconds: 88,
        sampleCountLastHour: 0,
        sampleCountToday: 6,
        sampleCountWeek: 10,
        busy: false,
      );
      final couple = computeGenerationEta(
        stats: coupleStats,
        elapsedSeconds: 0,
        personCount: 2,
        hasAiPreview: false,
        polishingStarted: false,
        hasServerPreviews: false,
        pipelineProgress: 0,
      );
      final solo = computeGenerationEta(
        stats: coupleStats,
        elapsedSeconds: 0,
        personCount: 1,
        hasAiPreview: false,
        polishingStarted: false,
        hasServerPreviews: false,
        pipelineProgress: 0,
      );
      expect(couple.estimatedTotalSeconds, solo.estimatedTotalSeconds + 8);
    });

    test('uses today average when hour samples are sparse', () {
      const todayStats = GenerationTimingStats(
        p50Seconds: 70,
        p90Seconds: 130,
        lastHourAvgSeconds: 95,
        todayAvgSeconds: 100,
        sampleCountLastHour: 1,
        sampleCountToday: 8,
        sampleCountWeek: 20,
        busy: false,
      );
      final eta = computeGenerationEta(
        stats: todayStats,
        elapsedSeconds: 0,
        personCount: 1,
        hasAiPreview: false,
        polishingStarted: false,
        hasServerPreviews: false,
        pipelineProgress: 0,
      );
      expect(eta.estimatedTotalSeconds, 100);
    });

    test('recent-week context when today samples are sparse', () {
      const weekStats = GenerationTimingStats(
        p50Seconds: 72,
        p90Seconds: 130,
        lastHourAvgSeconds: 95,
        todayAvgSeconds: 88,
        sampleCountLastHour: 0,
        sampleCountToday: 1,
        sampleCountWeek: 12,
        busy: false,
      );
      final eta = computeGenerationEta(
        stats: weekStats,
        elapsedSeconds: 0,
        personCount: 1,
        hasAiPreview: false,
        polishingStarted: false,
        hasServerPreviews: false,
        pipelineProgress: 0,
      );
      expect(
        eta.contextLine,
        AppStrings.generationWaitEtaRecentAvg('1:12'),
      );
    });

    test('falls back to static expectation without history', () {
      final eta = computeGenerationEta(
        stats: GenerationTimingStats.defaults,
        elapsedSeconds: 0,
        personCount: 1,
        hasAiPreview: false,
        polishingStarted: false,
        hasServerPreviews: false,
        pipelineProgress: 0,
      );
      expect(eta.contextLine, AppStrings.generationWaitTimeExpectation);
    });

    test('early in-progress still shows about-total primary', () {
      final eta = computeGenerationEta(
        stats: stats,
        elapsedSeconds: 10,
        personCount: 1,
        hasAiPreview: true,
        polishingStarted: false,
        hasServerPreviews: true,
        pipelineProgress: 0.2,
      );
      expect(eta.phase, GenerationEtaPhase.inProgress);
      expect(eta.primaryLine, contains('About'));
    });

    test('busy copy hidden during polishing', () {
      const busyStats = GenerationTimingStats(
        p50Seconds: 80,
        p90Seconds: 140,
        lastHourAvgSeconds: 120,
        todayAvgSeconds: 88,
        sampleCountLastHour: 6,
        sampleCountToday: 20,
        sampleCountWeek: 50,
        busy: true,
      );
      final eta = computeGenerationEta(
        stats: busyStats,
        elapsedSeconds: 100,
        personCount: 1,
        hasAiPreview: true,
        polishingStarted: true,
        hasServerPreviews: true,
        pipelineProgress: 0.8,
      );
      expect(eta.contextLine, AppStrings.generationWaitEtaTodayAvg('1:28'));
    });
  });

  group('GenerationTimingStats.fromJson', () {
    test('parses API payload', () {
      final stats = GenerationTimingStats.fromJson({
        'p50Seconds': 78,
        'p90Seconds': 142,
        'lastHourAvgSeconds': 95,
        'todayAvgSeconds': 88,
        'sampleCountLastHour': 12,
        'sampleCountToday': 40,
        'sampleCountWeek': 120,
        'busy': true,
      });
      expect(stats.p50Seconds, 78);
      expect(stats.busy, isTrue);
    });

    test('uses defaults for invalid JSON values', () {
      final stats = GenerationTimingStats.fromJson({
        'p50Seconds': 'nope',
        'busy': 'maybe',
      });
      expect(stats.p50Seconds, GenerationTimingStats.defaults.p50Seconds);
      expect(stats.busy, isFalse);
    });
  });
}
