import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_pipeline/pipeline_job.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_db.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_queue.dart';

void main() {
  late Directory dir;
  late EventPipelineDb db;
  late EventPipelineQueue queue;
  var clock = 1000;
  var ids = 0;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fz_evp_queue_');
    clock = 1000;
    ids = 0;
    db = (await EventPipelineDb.open(dir))!;
    queue = EventPipelineQueue(
      db: db,
      nowMs: () => clock,
      newId: () => 'j${ids++}',
    );
  });

  tearDown(() async {
    await db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('PipelineBackoff', () {
    test('first retry waits the base delay', () {
      expect(PipelineBackoff.delayFor(0), const Duration(seconds: 30));
    });

    test('doubles per attempt', () {
      expect(PipelineBackoff.delayFor(1), const Duration(minutes: 1));
      expect(PipelineBackoff.delayFor(2), const Duration(minutes: 2));
      expect(PipelineBackoff.delayFor(3), const Duration(minutes: 4));
    });

    test('caps at fifteen minutes', () {
      expect(PipelineBackoff.delayFor(10), const Duration(minutes: 15));
      expect(PipelineBackoff.delayFor(500), const Duration(minutes: 15));
    });

    test('exhausts at the attempt cap', () {
      expect(PipelineBackoff.isExhausted(7), isFalse);
      expect(PipelineBackoff.isExhausted(8), isTrue);
    });
  });

  group('enqueue', () {
    test('creates a pending job', () async {
      final job = await queue.enqueue(kind: 'print', mediaId: 'm1');
      expect(job.status, PipelineJobStatus.pending);
      expect(job.kind, 'print');
      expect(job.mediaId, 'm1');
    });

    test('is idempotent for the same kind and media', () async {
      final first = await queue.enqueue(kind: 'print', mediaId: 'm1');
      final second = await queue.enqueue(kind: 'print', mediaId: 'm1');
      expect(second.id, first.id);
      expect((await queue.counts('print')).total, 1);
    });

    test('different kinds for one item coexist', () async {
      await queue.enqueue(kind: 'ai', mediaId: 'm1');
      await queue.enqueue(kind: 'print', mediaId: 'm1');
      expect((await queue.counts('ai')).total, 1);
      expect((await queue.counts('print')).total, 1);
    });

    test('reviving a failed job reuses the row and resets attempts', () async {
      final job = await queue.enqueue(kind: 'print', mediaId: 'm1');
      await queue.markFailed(job.id, error: 'boom', retryable: false);
      final revived = await queue.enqueue(kind: 'print', mediaId: 'm1');
      expect(revived.id, job.id);
      expect(revived.status, PipelineJobStatus.pending);
      expect(revived.attempts, 0);
      expect(revived.lastError, isNull);
      expect((await queue.counts('print')).total, 1);
    });

    test('payload round-trips', () async {
      final job = await queue.enqueue(
        kind: 'print',
        mediaId: 'm1',
        payload: const {'copies': 2, 'size': 's6x8'},
      );
      final reloaded = await queue.findById(job.id);
      expect(reloaded!.payload['copies'], 2);
      expect(reloaded.payload['size'], 's6x8');
    });
  });

  group('claimReady', () {
    test('claims due pending jobs and marks them claimed', () async {
      await queue.enqueue(kind: 'print', mediaId: 'm1');
      final claimed = await queue.claimReady('print');
      expect(claimed, hasLength(1));
      final reloaded = await queue.findById(claimed.first.id);
      expect(reloaded!.status, PipelineJobStatus.claimed);
    });

    test('a second claim finds nothing still pending', () async {
      await queue.enqueue(kind: 'print', mediaId: 'm1');
      await queue.claimReady('print');
      expect(await queue.claimReady('print'), isEmpty);
    });

    test('respects the batch limit', () async {
      for (var i = 0; i < 5; i++) {
        await queue.enqueue(kind: 'print', mediaId: 'm$i');
      }
      expect(await queue.claimReady('print', limit: 2), hasLength(2));
    });

    test('does not claim another kind', () async {
      await queue.enqueue(kind: 'ai', mediaId: 'm1');
      expect(await queue.claimReady('print'), isEmpty);
    });

    test('does not claim a job still backing off', () async {
      final job = await queue.enqueue(kind: 'print', mediaId: 'm1');
      await queue.claimReady('print');
      await queue.markFailed(job.id, error: 'transient');
      expect(await queue.claimReady('print'), isEmpty);

      // One attempt made → 2^1 × 30s = 60s before it is claimable again.
      clock += const Duration(seconds: 61).inMilliseconds;
      expect(await queue.claimReady('print'), hasLength(1));
    });

    test('never claims a paused job', () async {
      await queue.enqueue(kind: 'print', mediaId: 'm1');
      await queue.pauseKind('print', reason: 'ribbon out');
      expect(await queue.claimReady('print'), isEmpty);
    });
  });

  group('failure handling', () {
    test('a retryable failure stays pending and schedules a retry', () async {
      final job = await queue.enqueue(kind: 'print', mediaId: 'm1');
      final status = await queue.markFailed(job.id, error: 'net');
      expect(status, PipelineJobStatus.pending);
      final reloaded = await queue.findById(job.id);
      expect(reloaded!.attempts, 1);
      expect(reloaded.nextAttemptAtMs, greaterThan(clock));
      expect(reloaded.lastError, 'net');
    });

    test('a non-retryable failure is terminal immediately', () async {
      final job = await queue.enqueue(kind: 'print', mediaId: 'm1');
      final status =
          await queue.markFailed(job.id, error: 'bad data', retryable: false);
      expect(status, PipelineJobStatus.failed);
      expect((await queue.findById(job.id))!.attempts, 1);
    });

    test('fails permanently once the attempt cap is reached', () async {
      final job = await queue.enqueue(kind: 'print', mediaId: 'm1');
      String status = PipelineJobStatus.pending;
      for (var i = 0; i < PipelineBackoff.maxAttempts; i++) {
        status = await queue.markFailed(job.id, error: 'again');
      }
      expect(status, PipelineJobStatus.failed);
      expect((await queue.findById(job.id))!.attempts,
          PipelineBackoff.maxAttempts);
    });

    test('deferJob requeues without consuming an attempt', () async {
      final job = await queue.enqueue(kind: 'ai', mediaId: 'm1');
      await queue.claimReady('ai');
      await queue.deferJob(job.id);
      final reloaded = await queue.findById(job.id);
      expect(reloaded!.status, PipelineJobStatus.pending);
      expect(reloaded.attempts, 0, reason: 'waiting is not failing');
      expect(reloaded.nextAttemptAtMs, greaterThan(clock));
    });
  });

  group('pause and resume', () {
    test('pause holds open jobs without consuming attempts', () async {
      for (var i = 0; i < 3; i++) {
        await queue.enqueue(kind: 'print', mediaId: 'm$i');
      }
      expect(await queue.pauseKind('print', reason: 'paper end'), 3);
      final counts = await queue.counts('print');
      expect(counts.paused, 3);
      expect(counts.failed, 0);
      expect(await queue.isKindPaused('print'), isTrue);
    });

    test('resume releases immediately, clearing the backoff', () async {
      final job = await queue.enqueue(kind: 'print', mediaId: 'm1');
      await queue.markFailed(job.id, error: 'x');
      await queue.pauseKind('print');
      expect(await queue.resumeKind('print'), 1);
      final reloaded = await queue.findById(job.id);
      expect(reloaded!.status, PipelineJobStatus.pending);
      expect(reloaded.nextAttemptAtMs, 0);
      expect(await queue.claimReady('print'), hasLength(1));
    });

    test('pause does not touch other kinds', () async {
      await queue.enqueue(kind: 'ai', mediaId: 'm1');
      await queue.enqueue(kind: 'print', mediaId: 'm1');
      await queue.pauseKind('print');
      expect((await queue.counts('ai')).pending, 1);
    });
  });

  group('cancel and retry', () {
    test('cancelFor withdraws an open job', () async {
      await queue.enqueue(kind: 'ai', mediaId: 'm1');
      expect(await queue.cancelFor(kind: 'ai', mediaId: 'm1'), 1);
      final counts = await queue.counts('ai');
      expect(counts.cancelled, 1);
      expect(counts.open, 0);
    });

    test('cancelFor leaves a completed job alone', () async {
      final job = await queue.enqueue(kind: 'ai', mediaId: 'm1');
      await queue.markDone(job.id);
      expect(await queue.cancelFor(kind: 'ai', mediaId: 'm1'), 0);
      expect((await queue.counts('ai')).done, 1);
    });

    test('retryFailed requeues failures with a clean slate', () async {
      final job = await queue.enqueue(kind: 'print', mediaId: 'm1');
      await queue.markFailed(job.id, error: 'x', retryable: false);
      expect(await queue.retryFailed('print'), 1);
      final reloaded = await queue.findById(job.id);
      expect(reloaded!.status, PipelineJobStatus.pending);
      expect(reloaded.attempts, 0);
      expect(reloaded.lastError, isNull);
    });
  });

  test('counts summarise every status', () async {
    final a = await queue.enqueue(kind: 'print', mediaId: 'm1');
    final b = await queue.enqueue(kind: 'print', mediaId: 'm2');
    await queue.enqueue(kind: 'print', mediaId: 'm3');
    await queue.markDone(a.id);
    await queue.markFailed(b.id, error: 'x', retryable: false);
    final counts = await queue.counts('print');
    expect(counts.done, 1);
    expect(counts.failed, 1);
    expect(counts.pending, 1);
    expect(counts.open, 1);
    expect(counts.total, 3);
  });
}
