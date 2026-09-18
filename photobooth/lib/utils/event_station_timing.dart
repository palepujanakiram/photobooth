/// Queue / processing clocks for event station rows.
class EventStationJobTimes {
  const EventStationJobTimes({
    this.createdAt,
    this.claimedAt,
    this.completedAt,
    this.rawStatus = '',
    this.errorMessage,
  });

  final DateTime? createdAt;
  final DateTime? claimedAt;
  final DateTime? completedAt;
  final String rawStatus;
  final String? errorMessage;

  bool get isFailed => rawStatus.toUpperCase() == 'FAILED';
  bool get isSkipped => rawStatus.toUpperCase() == 'SKIPPED';

  factory EventStationJobTimes.fromJson(Map<String, dynamic> json) {
    return EventStationJobTimes(
      createdAt: parseEventStationDate(
        json['createdAt'] ?? json['created_at'],
      ),
      claimedAt: parseEventStationDate(
        json['claimedAt'] ?? json['claimed_at'],
      ),
      completedAt: parseEventStationDate(
        json['completedAt'] ?? json['completed_at'],
      ),
      rawStatus: (json['rawStatus'] ?? json['raw_status'] ?? json['status'] ?? '')
          .toString()
          .trim()
          .toUpperCase(),
      errorMessage: _trimToNull(json['errorMessage'] ?? json['error_message']),
    );
  }
}

DateTime? parseEventStationDate(dynamic raw) {
  if (raw is DateTime) return raw;
  if (raw is int) {
    if (raw <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
  }
  if (raw is String && raw.trim().isNotEmpty) {
    return DateTime.tryParse(raw.trim());
  }
  return null;
}

/// Compact age: `12s`, `8m`, `1h 3m`.
String formatEventStationAge(DateTime? at, {DateTime? now}) {
  if (at == null) return '—';
  return formatEventStationDuration((now ?? DateTime.now()).difference(at));
}

String formatEventStationDuration(Duration elapsed) {
  final d = elapsed.isNegative ? Duration.zero : elapsed;
  if (d.inSeconds < 60) return '${d.inSeconds}s';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}

/// Wait since enqueue, plus processing time after claim (or until now).
String eventStationQueueSummary(
  EventStationJobTimes times, {
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  final queued = formatEventStationAge(times.createdAt, now: clock);
  final start = times.claimedAt;
  if (start == null) {
    return 'Queued $queued';
  }
  final end = times.completedAt ?? clock;
  final processing = formatEventStationDuration(end.difference(start));
  return 'Queued $queued · $processing processing';
}

String eventStationDisplayStatus(String status, EventStationJobTimes times) {
  if (times.isFailed) return 'FAILED';
  if (times.isSkipped) return 'SKIPPED';
  final raw = times.rawStatus;
  if (raw == 'PRINTING') return raw;
  return status.trim().isEmpty ? 'PENDING' : status.trim().toUpperCase();
}

String? _trimToNull(dynamic raw) {
  final s = raw?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}
