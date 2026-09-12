import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../models/event_pipeline/pipeline_job.dart';
import 'event_pipeline_db.dart';

/// Open/failed/done tallies for one job kind.
class PipelineJobCounts {
  const PipelineJobCounts({
    this.pending = 0,
    this.claimed = 0,
    this.paused = 0,
    this.done = 0,
    this.failed = 0,
    this.cancelled = 0,
  });

  final int pending;
  final int claimed;
  final int paused;
  final int done;
  final int failed;
  final int cancelled;

  int get open => pending + claimed + paused;
  int get total => open + done + failed + cancelled;

  factory PipelineJobCounts.fromStatusMap(Map<String, int> byStatus) {
    return PipelineJobCounts(
      pending: byStatus[PipelineJobStatus.pending] ?? 0,
      claimed: byStatus[PipelineJobStatus.claimed] ?? 0,
      paused: byStatus[PipelineJobStatus.paused] ?? 0,
      done: byStatus[PipelineJobStatus.done] ?? 0,
      failed: byStatus[PipelineJobStatus.failed] ?? 0,
      cancelled: byStatus[PipelineJobStatus.cancelled] ?? 0,
    );
  }
}

/// Durable work queue over `evp_pipeline_jobs`.
class EventPipelineQueue {
  EventPipelineQueue({
    required EventPipelineDb db,
    int Function()? nowMs,
    String Function()? newId,
  })  : _db = db.database,
        _nowMs = nowMs ?? _defaultNowMs,
        _newId = newId ?? _defaultNewId;

  final Database _db;
  final int Function() _nowMs;
  final String Function() _newId;

  static int _defaultNowMs() => DateTime.now().millisecondsSinceEpoch;
  static int _idCounter = 0;
  static String _defaultNewId() =>
      'pj-${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

  /// Enqueues a job, or returns the existing one for `(kind, mediaId)`.
  ///
  /// Idempotent by unique index, so a retried enqueue after a crash mid-advance
  /// cannot create a duplicate. A previously **cancelled or failed** job for the
  /// same pair is revived instead — that is what makes an operator retry work
  /// without a second row appearing.
  Future<PipelineJob> enqueue({
    required String kind,
    required String mediaId,
    String? eventId,
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) async {
    final existing = await findFor(kind: kind, mediaId: mediaId);
    if (existing != null) {
      if (existing.isOpen) return existing;
      return _revive(existing, payload: payload);
    }

    final now = _nowMs();
    final job = PipelineJob(
      id: _newId(),
      kind: kind,
      mediaId: mediaId,
      eventId: eventId,
      payload: payload,
      status: PipelineJobStatus.pending,
      createdAtMs: now,
      updatedAtMs: now,
    );
    try {
      await _db.insert('evp_pipeline_jobs', job.toRow());
      return job;
    } on DatabaseException catch (e) {
      if (!e.isUniqueConstraintError()) rethrow;
      final winner = await findFor(kind: kind, mediaId: mediaId);
      if (winner == null) rethrow;
      return winner;
    }
  }

  Future<PipelineJob> _revive(
    PipelineJob job, {
    required Map<String, dynamic> payload,
  }) async {
    final now = _nowMs();
    await _db.update(
      'evp_pipeline_jobs',
      <String, Object?>{
        'status': PipelineJobStatus.pending,
        'attempts': 0,
        'next_attempt_at_ms': 0,
        'last_error': null,
        'payload_json': jsonEncode(payload),
        'updated_at_ms': now,
      },
      where: 'id = ?',
      whereArgs: [job.id],
    );
    return (await findById(job.id))!;
  }

  /// Claims up to [limit] jobs of [kind] that are due.
  ///
  /// Paused jobs are skipped without consuming attempts — a printer out of
  /// ribbon must not exhaust the retry budget and fail a whole event.
  Future<List<PipelineJob>> claimReady(String kind, {int limit = 4}) async {
    // The operator's hold. One chokepoint suspends every stage at once, which
    // is what Pause has to mean — a ribbon change or a printer being moved is
    // not a per-stage event.
    if (await isPaused()) return const <PipelineJob>[];
    final now = _nowMs();
    final rows = await _db.query(
      'evp_pipeline_jobs',
      where: 'kind = ? AND status = ? AND next_attempt_at_ms <= ?',
      whereArgs: [kind, PipelineJobStatus.pending, now],
      orderBy: 'created_at_ms ASC',
      limit: limit,
    );
    final claimed = <PipelineJob>[];
    for (final row in rows) {
      final job = PipelineJob.fromRow(row);
      final n = await _db.update(
        'evp_pipeline_jobs',
        <String, Object?>{
          'status': PipelineJobStatus.claimed,
          // Stamped once, on the transition into work, so a retry does not
          // erase how long the first attempt took.
          'started_at_ms': now,
          'updated_at_ms': now,
        },
        // Re-check status so two drains racing cannot both claim the same job.
        where: 'id = ? AND status = ?',
        whereArgs: [job.id, PipelineJobStatus.pending],
      );
      if (n == 1) claimed.add(job);
    }
    return claimed;
  }

  Future<void> markDone(String id) async {
    await _db.update(
      'evp_pipeline_jobs',
      <String, Object?>{
        'status': PipelineJobStatus.done,
        'last_error': null,
        'updated_at_ms': _nowMs(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Records a failure and schedules the retry.
  ///
  /// A non-retryable error fails immediately; a retryable one backs off until
  /// [PipelineBackoff.maxAttempts] is reached. Returns the resulting status.
  Future<String> markFailed(
    String id, {
    required String error,
    bool retryable = true,
  }) async {
    final job = await findById(id);
    if (job == null) return PipelineJobStatus.failed;
    final attempts = job.attempts + 1;
    final now = _nowMs();
    final exhausted = !retryable || PipelineBackoff.isExhausted(attempts);
    final status =
        exhausted ? PipelineJobStatus.failed : PipelineJobStatus.pending;
    await _db.update(
      'evp_pipeline_jobs',
      <String, Object?>{
        'status': status,
        'attempts': attempts,
        'next_attempt_at_ms':
            exhausted ? 0 : PipelineBackoff.nextAttemptAt(now, attempts),
        'last_error': error,
        'updated_at_ms': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    return status;
  }

  /// After a crash, `CLAIMED` jobs are orphans: [claimReady] only picks
  /// `PENDING`, so a photo that was on the printer when the process died would
  /// sit at Printing forever. Putting them back on the queue is the restart
  /// recovery. [mediaId] scopes it to one item (Reprint of a stuck job).
  Future<int> releaseClaimed(String kind, {String? mediaId}) async {
    final now = _nowMs();
    final scoped = mediaId != null;
    return _db.update(
      'evp_pipeline_jobs',
      <String, Object?>{
        'status': PipelineJobStatus.pending,
        'next_attempt_at_ms': 0,
        'updated_at_ms': now,
      },
      where: scoped
          ? 'kind = ? AND status = ? AND media_id = ?'
          : 'kind = ? AND status = ?',
      whereArgs: scoped
          ? <Object?>[kind, PipelineJobStatus.claimed, mediaId]
          : <Object?>[kind, PipelineJobStatus.claimed],
    );
  }

  /// Returns a claimed job to the queue **without** counting an attempt.
  ///
  /// For a precondition that is not the job's fault — an AI job whose media item
  /// has no `remote_session_id` yet. Such items must wait, not burn retries.
  Future<void> deferJob(String id, {Duration delay = const Duration(minutes: 1)}) async {
    final now = _nowMs();
    await _db.update(
      'evp_pipeline_jobs',
      <String, Object?>{
        'status': PipelineJobStatus.pending,
        'next_attempt_at_ms': now + delay.inMilliseconds,
        'updated_at_ms': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Holds every open job of [kind] — e.g. the printer needs new media.
  Future<int> pauseKind(String kind, {String? reason}) async {
    return _db.update(
      'evp_pipeline_jobs',
      <String, Object?>{
        'status': PipelineJobStatus.paused,
        if (reason != null) 'last_error': reason,
        'updated_at_ms': _nowMs(),
      },
      where: 'kind = ? AND status IN (?, ?)',
      whereArgs: [kind, PipelineJobStatus.pending, PipelineJobStatus.claimed],
    );
  }

  /// Releases a paused kind, clearing the backoff so work resumes immediately.
  Future<int> resumeKind(String kind) async {
    return _db.update(
      'evp_pipeline_jobs',
      <String, Object?>{
        'status': PipelineJobStatus.pending,
        'next_attempt_at_ms': 0,
        'last_error': null,
        'updated_at_ms': _nowMs(),
      },
      where: 'kind = ? AND status = ?',
      whereArgs: [kind, PipelineJobStatus.paused],
    );
  }

  /// Withdraws open jobs, e.g. the `ai` job of an item the operator skipped.
  Future<int> cancelFor({required String kind, required String mediaId}) async {
    return _db.update(
      'evp_pipeline_jobs',
      <String, Object?>{
        'status': PipelineJobStatus.cancelled,
        'updated_at_ms': _nowMs(),
      },
      where: 'kind = ? AND media_id = ? AND status IN (?, ?, ?)',
      whereArgs: [
        kind,
        mediaId,
        PipelineJobStatus.pending,
        PipelineJobStatus.claimed,
        PipelineJobStatus.paused,
      ],
    );
  }

  /// Requeues failed jobs of [kind] — the console's retry button.
  Future<int> retryFailed(String kind) async {
    return _db.update(
      'evp_pipeline_jobs',
      <String, Object?>{
        'status': PipelineJobStatus.pending,
        'attempts': 0,
        'next_attempt_at_ms': 0,
        'last_error': null,
        'updated_at_ms': _nowMs(),
      },
      where: 'kind = ? AND status = ?',
      whereArgs: [kind, PipelineJobStatus.failed],
    );
  }

  /// Requeues one item's failed job of [kind] — the selection-scoped retry.
  ///
  /// Distinct from [retryFailed], which reaches every failure of a kind. The
  /// queue screen only ever acts on what the operator ticked, so it needs a
  /// per-item form.
  Future<int> retryFor({
    required String kind,
    required String mediaId,
  }) async {
    return _db.update(
      'evp_pipeline_jobs',
      <String, Object?>{
        'status': PipelineJobStatus.pending,
        'attempts': 0,
        'next_attempt_at_ms': 0,
        'last_error': null,
        'updated_at_ms': _nowMs(),
      },
      where: 'kind = ? AND media_id = ? AND status = ?',
      whereArgs: [kind, mediaId, PipelineJobStatus.failed],
    );
  }

  /// Open print jobs in the order they will actually run.
  ///
  /// One item is `CLAIMED` and genuinely on the printer; the rest are waiting.
  /// The queue screen needs the distinction because showing forty photos as
  /// "Printing" is simply untrue, and an operator watching for their print to
  /// come out has no way to tell how far down it is.
  Future<List<PipelineJob>> openJobsInOrder(String kind) async {
    final rows = await _db.query(
      'evp_pipeline_jobs',
      where: 'kind = ? AND status IN (?, ?)',
      whereArgs: [kind, PipelineJobStatus.claimed, PipelineJobStatus.pending],
      // Claimed first: it is the one on the printer right now.
      orderBy: "CASE status WHEN 'CLAIMED' THEN 0 ELSE 1 END, created_at_ms ASC",
    );
    return [for (final r in rows) PipelineJob.fromRow(r)];
  }

  /// Deletes every job belonging to [mediaId], for an item being removed.
  Future<int> deleteFor(String mediaId) async {
    return _db.delete(
      'evp_pipeline_jobs',
      where: 'media_id = ?',
      whereArgs: [mediaId],
    );
  }

  // -------------------------------------------------------------------- reads

  Future<PipelineJob?> findById(String id) async {
    final rows = await _db.query(
      'evp_pipeline_jobs',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PipelineJob.fromRow(rows.first);
  }

  Future<List<PipelineJob>> listUpdatedSince(int sinceMs, {String? eventId}) async {
    final id = eventId?.trim() ?? '';
    final where = id.isEmpty
        ? 'updated_at_ms > ?'
        : 'updated_at_ms > ? AND event_id = ?';
    final args = id.isEmpty ? <Object?>[sinceMs] : <Object?>[sinceMs, id];
    final rows = await _db.query(
      'evp_pipeline_jobs',
      where: where,
      whereArgs: args,
      orderBy: 'updated_at_ms ASC',
      limit: 500,
    );
    return [for (final r in rows) PipelineJob.fromRow(r)];
  }

  Future<void> upsertFromRemote(PipelineJob incoming) async {
    if (incoming.id.trim().isEmpty) return;
    final existing = await findById(incoming.id);
    if (existing != null && existing.updatedAtMs > incoming.updatedAtMs) {
      return;
    }
    await _db.insert(
      'evp_pipeline_jobs',
      incoming.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<PipelineJob?> findFor({
    required String kind,
    required String mediaId,
  }) async {
    final rows = await _db.query(
      'evp_pipeline_jobs',
      where: 'kind = ? AND media_id = ?',
      whereArgs: [kind, mediaId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PipelineJob.fromRow(rows.first);
  }

  Future<List<PipelineJob>> listByStatus(String kind, String status) async {
    final rows = await _db.query(
      'evp_pipeline_jobs',
      where: 'kind = ? AND status = ?',
      whereArgs: [kind, status],
      orderBy: 'created_at_ms ASC',
    );
    return [for (final r in rows) PipelineJob.fromRow(r)];
  }

  Future<PipelineJobCounts> counts(String kind) async {
    final rows = await _db.rawQuery(
      'SELECT status, COUNT(*) AS n FROM evp_pipeline_jobs '
      'WHERE kind = ? GROUP BY status',
      [kind],
    );
    return PipelineJobCounts.fromStatusMap({
      for (final r in rows)
        (r['status'] ?? '').toString(): (r['n'] as int?) ?? 0,
    });
  }

  /// Whether the operator has held the whole queue.
  ///
  /// Stored in `evp_meta` rather than derived from job rows, and that is the
  /// point: it is **queue state, not screen state**, so it survives a restart,
  /// and pausing an empty queue still holds the work that arrives next. Reading
  /// it off the rows would make both of those silently untrue.
  Future<bool> isPaused() async {
    final rows = await _db.query(
      'evp_meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_kPausedKey],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    return (rows.first['value'] ?? '').toString() == '1';
  }

  /// Holds or releases every stage. Returns the new state.
  Future<bool> setPaused(bool paused) async {
    await _db.insert(
      'evp_meta',
      <String, Object?>{'key': _kPausedKey, 'value': paused ? '1' : '0'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (!paused) {
      // Clear any backoff so resuming actually resumes, rather than waiting out
      // a delay set before the operator paused.
      for (final kind in const <String>['ai', 'frame', 'print']) {
        await resumeKind(kind);
      }
    }
    return paused;
  }

  static const String _kPausedKey = 'queue_paused';

  /// True when at least one job of [kind] is waiting on a pause.
  Future<bool> isKindPaused(String kind) async {
    final rows = await _db.query(
      'evp_pipeline_jobs',
      columns: ['id'],
      where: 'kind = ? AND status = ?',
      whereArgs: [kind, PipelineJobStatus.paused],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}
