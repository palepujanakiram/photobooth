/// Rolling generation timing from `GET /api/kiosk/generation-timing`.
class GenerationTimingStats {
  const GenerationTimingStats({
    required this.p50Seconds,
    required this.p90Seconds,
    required this.lastHourAvgSeconds,
    required this.todayAvgSeconds,
    required this.sampleCountLastHour,
    required this.sampleCountToday,
    required this.sampleCountWeek,
    required this.busy,
  });

  final int p50Seconds;
  final int p90Seconds;
  final int lastHourAvgSeconds;
  final int todayAvgSeconds;
  final int sampleCountLastHour;
  final int sampleCountToday;
  final int sampleCountWeek;
  final bool busy;

  static const GenerationTimingStats defaults = GenerationTimingStats(
    p50Seconds: 90,
    p90Seconds: 150,
    lastHourAvgSeconds: 90,
    todayAvgSeconds: 90,
    sampleCountLastHour: 0,
    sampleCountToday: 0,
    sampleCountWeek: 0,
    busy: false,
  );

  factory GenerationTimingStats.fromJson(Map<String, dynamic> json) {
    int readInt(String key, int fallback) {
      final v = json[key];
      if (v is num) return v.round().clamp(1, 600);
      return fallback;
    }

    return GenerationTimingStats(
      p50Seconds: readInt('p50Seconds', defaults.p50Seconds),
      p90Seconds: readInt('p90Seconds', defaults.p90Seconds),
      lastHourAvgSeconds:
          readInt('lastHourAvgSeconds', defaults.lastHourAvgSeconds),
      todayAvgSeconds: readInt('todayAvgSeconds', defaults.todayAvgSeconds),
      sampleCountLastHour: readInt('sampleCountLastHour', 0),
      sampleCountToday: readInt('sampleCountToday', 0),
      sampleCountWeek: readInt('sampleCountWeek', 0),
      busy: json['busy'] == true,
    );
  }
}
