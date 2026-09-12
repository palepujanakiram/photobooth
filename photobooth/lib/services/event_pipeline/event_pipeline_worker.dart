import 'dart:async';

import '../../models/event_pipeline/pipeline_job.dart';
import '../../utils/exceptions.dart';
import '../../utils/logger.dart';
import 'event_pipeline_queue.dart';

/// Outcome a stage reports back to the worker.
enum JobOutcome {
  /// Work finished. Advance the item to its next step.
  done,

  /// Failed, but worth retrying — backoff and count an attempt.
  retry,

  /// Failed permanently. No further attempts.
  fail,

  /// A precondition is not met yet through no fault of this job (an AI job
  /// waiting on `remote_session_id`). Requeued **without** counting an attempt.
  defer,

  /// The whole kind should stop — printer out of ribbon or paper. Pauses every
  /// open job of this kind rather than burning eight attempts each.
  pause,
}

class JobResult {
  const JobResult(this.outcome, {this.error, this.retryAfter});

  const JobResult.done() : this(JobOutcome.done);
  const JobResult.retry(String message) : this(JobOutcome.retry, error: message);
  const JobResult.fail(String message) : this(JobOutcome.fail, error: message);

  /// [retryAfter] paces the wait to what is actually being waited on: a job
  /// blocked on another worker should come back quickly, while one blocked on a
  /// link that is down for the session should not poll every minute.
  const JobResult.defer([String? message, Duration? retryAfter])
      : this(JobOutcome.defer, error: message, retryAfter: retryAfter);

  const JobResult.pause(String message) : this(JobOutcome.pause, error: message);

  final JobOutcome outcome;
  final String? error;

  /// How long to hold a deferred job. Null uses the queue's default.
  final Duration? retryAfter;
}

/// True when an error is worth another attempt rather than a permanent failure.
///
/// Modelled on `isRetryableIngestError` in `kiosk_outbox_worker.dart`: default to
/// retrying, because a transient network or hardware fault is far more common
/// here than a genuinely unprocessable job, and a wrongly-permanent failure
/// loses a guest's photo.
bool isRetryableEventError(Object error) {
  if (error is ApiException) {
    final code = error.statusCode;
    if (code == null) return true;
    // 4xx other than the "not ready yet" and rate-limit cases is our bug or bad
    // data; retrying it just burns the budget.
    if (code == 408 || code == 409 || code == 412 || code == 429) return true;
    if (code >= 400 && code < 500) return false;
    return true;
  }
  return true;
}

/// Drain loop shared by the AI, frame and print stages.
///
/// The shape — a `_chain` future serialising every pass, a `Timer.periodic`
/// driving it, and claim → process → mark — is lifted from [KioskOutboxWorker],
/// which has been running this pattern in production. It is copied rather than
/// imported so the event pipeline stays self-contained.
abstract class EventPipelineWorker {
  EventPipelineWorker({
    required EventPipelineQueue queue,
    required this.kind,
    this.batchLimit = 4,
  }) : _queue = queue;

  final EventPipelineQueue _queue;

  /// Job kind this worker drains — one of `EventPipelineStep`.
  final String kind;

  final int batchLimit;

  Timer? _timer;
  Future<void> _chain = Future<void>.value();
  bool _draining = false;

  EventPipelineQueue get queue => _queue;
  bool get isRunning => _timer != null;

  /// Runs one job. Implementations must not throw; return a [JobResult]
  /// instead. A thrown error is still caught, but loses the retry classification.
  Future<JobResult> process(PipelineJob job);

  /// Called after a job completes so the ledger can advance the item's step.
  Future<void> onJobDone(PipelineJob job) async {}

  /// Called when a job reaches a terminal failure.
  Future<void> onJobFailed(PipelineJob job, String error) async {}

  void start({Duration interval = const Duration(seconds: 5)}) {
    if (_timer != null) return;
    unawaited(_recoverAndDrain());
    _timer = Timer.periodic(interval, (_) => unawaited(drain()));
  }

  /// A `CLAIMED` row left behind by a crash is otherwise never picked up again.
  Future<void> _recoverAndDrain() async {
    try {
      await _queue.releaseClaimed(kind);
      await drain();
    } catch (e) {
      // Tests and teardown close SQLite while this is still in flight.
      AppLogger.debug('EventPipelineWorker($kind) recover skipped: $e');
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Drains one batch. Serialised so overlapping timer ticks cannot double-run.
  Future<int> drain({int? limit}) {
    final done = Completer<int>();
    _chain = _chain.then((_) async {
      try {
        done.complete(await _drainUnlocked(limit ?? batchLimit));
      } catch (e, st) {
        AppLogger.error(
          'EventPipelineWorker($kind) drain failed',
          error: e,
          stackTrace: st,
        );
        done.complete(0);
      }
    });
    return done.future;
  }

  /// Drains repeatedly until nothing is ready, for a manual "run now" action.
  ///
  /// [maxRounds] bounds the loop so a job that immediately requeues itself
  /// cannot spin forever.
  Future<int> drainUntilIdle({int maxRounds = 200}) async {
    var total = 0;
    for (var round = 0; round < maxRounds; round++) {
      final n = await drain();
      if (n == 0) break;
      total += n;
    }
    return total;
  }

  Future<int> _drainUnlocked(int limit) async {
    if (_draining) return 0;
    _draining = true;
    try {
      final jobs = await _queue.claimReady(kind, limit: limit);
      var completed = 0;
      for (final job in jobs) {
        if (await _runOne(job)) completed++;
      }
      return completed;
    } finally {
      _draining = false;
    }
  }

  Future<bool> _runOne(PipelineJob job) async {
    JobResult result;
    try {
      result = await process(job);
    } catch (e, st) {
      AppLogger.error(
        'EventPipelineWorker($kind) job ${job.id} threw',
        error: e,
        stackTrace: st,
      );
      result = isRetryableEventError(e)
          ? JobResult.retry(e.toString())
          : JobResult.fail(e.toString());
    }
    return _applyResult(job, result);
  }

  Future<bool> _applyResult(PipelineJob job, JobResult result) async {
    switch (result.outcome) {
      case JobOutcome.done:
        await _queue.markDone(job.id);
        await onJobDone(job);
        return true;
      case JobOutcome.defer:
        final after = result.retryAfter;
        await _queue.deferJob(
          job.id,
          delay: after ?? const Duration(minutes: 1),
        );
        return false;
      case JobOutcome.pause:
        await _queue.pauseKind(kind, reason: result.error);
        return false;
      case JobOutcome.retry:
      case JobOutcome.fail:
        return _applyFailure(job, result);
    }
  }

  Future<bool> _applyFailure(PipelineJob job, JobResult result) async {
    final error = result.error ?? 'unknown error';
    final status = await _queue.markFailed(
      job.id,
      error: error,
      retryable: result.outcome == JobOutcome.retry,
    );
    if (status == PipelineJobStatus.failed) {
      await onJobFailed(job, error);
    }
    return false;
  }
}
