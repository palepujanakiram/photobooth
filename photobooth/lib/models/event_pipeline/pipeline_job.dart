import 'dart:convert';

import '../../utils/json_parse_helpers.dart';

/// Job lifecycle. `PAUSED` and `CANCELLED` both stop work without consuming
/// attempts, but mean different things: paused is a temporary hold the queue
/// itself applies, cancelled is an operator decision that will not be resumed.
abstract final class PipelineJobStatus {
  static const String pending = 'PENDING';
  static const String claimed = 'CLAIMED';
  static const String done = 'DONE';
  static const String failed = 'FAILED';

  /// Held by the queue — e.g. the printer is out of ribbon. Resumable.
  ///
  /// This exists so a consumables fault does not burn the retry budget: without
  /// it, eight attempts against an empty printer mark a whole event failed.
  static const String paused = 'PAUSED';

  /// Withdrawn by an operator, e.g. **Skip AI**. Not resumable.
  static const String cancelled = 'CANCELLED';

  static const List<String> open = <String>[pending, claimed, paused];
  static const List<String> terminal = <String>[done, failed, cancelled];
}

/// One unit of work against one media item.
class PipelineJob {
  const PipelineJob({
    required this.id,
    required this.kind,
    required this.mediaId,
    required this.status,
    required this.createdAtMs,
    this.startedAtMs,
    required this.updatedAtMs,
    this.eventId,
    this.payload = const <String, dynamic>{},
    this.attempts = 0,
    this.nextAttemptAtMs = 0,
    this.lastError,
  });

  final String id;

  /// One of [EventPipelineStep] — `ai`, `frame`, or `print`.
  final String kind;

  final String mediaId;
  final String? eventId;
  final Map<String, dynamic> payload;

  /// One of [PipelineJobStatus].
  final String status;

  final int attempts;

  /// Earliest wall-clock time this job may be claimed again.
  final int nextAttemptAtMs;

  final String? lastError;
  final int createdAtMs;

  /// When the work actually began — set on claim, null while still waiting.
  ///
  /// Separate from [createdAtMs] because the gap between the two is queue wait,
  /// not work: without it a photo that sat behind forty prints is
  /// indistinguishable from one that took four minutes to generate.
  final int? startedAtMs;

  final int updatedAtMs;

  bool get isOpen => PipelineJobStatus.open.contains(status);
  bool get isTerminal => PipelineJobStatus.terminal.contains(status);

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'kind': kind,
        'media_id': mediaId,
        'event_id': eventId,
        'payload_json': jsonEncode(payload),
        'status': status,
        'attempts': attempts,
        'next_attempt_at_ms': nextAttemptAtMs,
        'last_error': lastError,
        'created_at_ms': createdAtMs,
        'started_at_ms': startedAtMs,
        'updated_at_ms': updatedAtMs,
      };

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'kind': kind,
        'mediaId': mediaId,
        'eventId': eventId,
        'payload': payload,
        'status': status,
        'attempts': attempts,
        'nextAttemptAtMs': nextAttemptAtMs,
        'lastError': lastError,
        'createdAtMs': createdAtMs,
        'startedAtMs': startedAtMs,
        'updatedAtMs': updatedAtMs,
      };

  factory PipelineJob.fromJson(Map<String, dynamic> json) {
    return PipelineJob(
      id: JsonParseHelpers.stringValue(json['id']),
      kind: JsonParseHelpers.stringValue(json['kind']),
      mediaId: JsonParseHelpers.stringValue(json['mediaId'] ?? json['media_id']),
      eventId: JsonParseHelpers.stringOrNull(json['eventId'] ?? json['event_id']),
      payload: _decodePayloadMap(json['payload'] ?? json['payload_json']),
      status: JsonParseHelpers.stringValue(
        json['status'],
        fallback: PipelineJobStatus.pending,
      ),
      attempts: JsonParseHelpers.intOrNull(json['attempts']) ?? 0,
      nextAttemptAtMs: JsonParseHelpers.intOrNull(
            json['nextAttemptAtMs'] ?? json['next_attempt_at_ms'],
          ) ??
          0,
      lastError: JsonParseHelpers.stringOrNull(json['lastError'] ?? json['last_error']),
      createdAtMs: JsonParseHelpers.intOrNull(
            json['createdAtMs'] ?? json['created_at_ms'],
          ) ??
          0,
      startedAtMs: JsonParseHelpers.intOrNull(
        json['startedAtMs'] ?? json['started_at_ms'],
      ),
      updatedAtMs: JsonParseHelpers.intOrNull(
            json['updatedAtMs'] ?? json['updated_at_ms'],
          ) ??
          0,
    );
  }

  static Map<String, dynamic> _decodePayloadMap(Object? raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) return _decodePayload(raw);
    return const <String, dynamic>{};
  }

  factory PipelineJob.fromRow(Map<String, Object?> row) {
    return PipelineJob(
      id: (row['id'] ?? '').toString(),
      kind: (row['kind'] ?? '').toString(),
      mediaId: (row['media_id'] ?? '').toString(),
      eventId: row['event_id'] as String?,
      payload: _decodePayload(row['payload_json'] as String?),
      status: (row['status'] ?? PipelineJobStatus.pending).toString(),
      attempts: (row['attempts'] as int?) ?? 0,
      nextAttemptAtMs: (row['next_attempt_at_ms'] as int?) ?? 0,
      lastError: row['last_error'] as String?,
      createdAtMs: (row['created_at_ms'] as int?) ?? 0,
      startedAtMs: row['started_at_ms'] as int?,
      updatedAtMs: (row['updated_at_ms'] as int?) ?? 0,
    );
  }

  static Map<String, dynamic> _decodePayload(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // A corrupt payload must not wedge the queue; the job runs with defaults
      // and fails loudly on its own terms if it genuinely needed the data.
    }
    return const <String, dynamic>{};
  }
}

/// Retry pacing shared by the pipeline queue and the mirror queue.
abstract final class PipelineBackoff {
  static const int maxAttempts = 8;
  static const Duration base = Duration(seconds: 30);
  static const Duration cap = Duration(minutes: 15);

  /// `min(2^attempts × 30s, 15min)`.
  ///
  /// [attempts] is the count *already* made. A caller increments before asking,
  /// so the first retry (attempts == 1) waits 60s and the cap is hit at 5.
  static Duration delayFor(int attempts) {
    if (attempts <= 0) return base;
    if (attempts >= 20) return cap;
    final ms = base.inMilliseconds * (1 << attempts);
    return ms >= cap.inMilliseconds ? cap : Duration(milliseconds: ms);
  }

  static int nextAttemptAt(int nowMs, int attempts) =>
      nowMs + delayFor(attempts).inMilliseconds;

  static bool isExhausted(int attempts) => attempts >= maxAttempts;
}
