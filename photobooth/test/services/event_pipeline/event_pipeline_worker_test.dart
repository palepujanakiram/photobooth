import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_pipeline/pipeline_job.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_db.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_queue.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_worker.dart';
import 'package:photobooth/utils/exceptions.dart';

/// Manual fake by subclass-and-override, matching the repo's test convention.
class FakeWorker extends EventPipelineWorker {
  FakeWorker({
    required super.queue,
    super.kind = 'print',
    super.batchLimit,
    this.handler,
  });

  Future<JobResult> Function(PipelineJob job)? handler;

  final List<String> processed = <String>[];
  final List<String> completed = <String>[];
  final List<String> failed = <String>[];

  @override
  Future<JobResult> process(PipelineJob job) async {
    processed.add(job.mediaId);
    final h = handler;
    if (h == null) return const JobResult.done();
    return h(job);
  }

  @override
  Future<void> onJobDone(PipelineJob job) async => completed.add(job.mediaId);

  @override
  Future<void> onJobFailed(PipelineJob job, String error) async =>
      failed.add(job.mediaId);
}

void main() {
  late Directory dir;
  late EventPipelineDb db;
  late EventPipelineQueue queue;
  late FakeWorker worker;
  var clock = 1000;
  var ids = 0;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fz_evp_worker_');
    clock = 1000;
    ids = 0;
    db = (await EventPipelineDb.open(dir))!;
    queue = EventPipelineQueue(
      db: db,
      nowMs: () => clock,
      newId: () => 'j${ids++}',
    );
    worker = FakeWorker(queue: queue);
  });

  tearDown(() async {
    worker.stop();
    await db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('isRetryableEventError', () {
    test('retries when there is no status code', () {
      expect(isRetryableEventError(ApiException('offline')), isTrue);
    });

    test('retries 5xx and transient 4xx', () {
      for (final code in [500, 502, 503, 408, 409, 412, 429]) {
        expect(
          isRetryableEventError(ApiException('x', code)),
          isTrue,
          reason: '$code should retry',
        );
      }
    });

    test('does not retry a client error we caused', () {
      for (final code in [400, 401, 403, 404, 422]) {
        expect(
          isRetryableEventError(ApiException('x', code)),
          isFalse,
          reason: '$code should not retry',
        );
      }
    });

    test('an unknown error retries rather than losing a photo', () {
      expect(isRetryableEventError(StateError('odd')), isTrue);
    });
  });

  group('drain', () {
    test('processes ready jobs and reports completions', () async {
      await queue.enqueue(kind: 'print', mediaId: 'm1');
      await queue.enqueue(kind: 'print', mediaId: 'm2');
      expect(await worker.drain(), 2);
      expect(worker.processed, ['m1', 'm2']);
      expect(worker.completed, ['m1', 'm2']);
      expect((await queue.counts('print')).done, 2);
    });

    test('an empty queue drains zero', () async {
      expect(await worker.drain(), 0);
      expect(worker.processed, isEmpty);
    });

    test('ignores jobs of another kind', () async {
      await queue.enqueue(kind: 'ai', mediaId: 'm1');
      expect(await worker.drain(), 0);
    });

    test('honours the batch limit', () async {
      for (var i = 0; i < 5; i++) {
        await queue.enqueue(kind: 'print', mediaId: 'm$i');
      }
      expect(await worker.drain(limit: 2), 2);
    });

    test('drainUntilIdle keeps going until nothing is ready', () async {
      for (var i = 0; i < 9; i++) {
        await queue.enqueue(kind: 'print', mediaId: 'm$i');
      }
      expect(await worker.drainUntilIdle(), 9);
      expect((await queue.counts('print')).done, 9);
    });

    test('overlapping drains do not double-process a job', () async {
      await queue.enqueue(kind: 'print', mediaId: 'm1');
      final results = await Future.wait([worker.drain(), worker.drain()]);
      expect(results.reduce((a, b) => a + b), 1);
      expect(worker.processed, ['m1']);
    });
  });

  group('outcomes', () {
    test('retry backs off and keeps the job open', () async {
      worker.handler = (_) async => const JobResult.retry('net down');
      await queue.enqueue(kind: 'print', mediaId: 'm1');
      expect(await worker.drain(), 0);

      final counts = await queue.counts('print');
      expect(counts.pending, 1);
      expect(counts.failed, 0);
      expect(worker.failed, isEmpty, reason: 'not terminal yet');
    });

    test('fail is terminal and reports once', () async {
      worker.handler = (_) async => const JobResult.fail('bad payload');
      await queue.enqueue(kind: 'print', mediaId: 'm1');
      await worker.drain();
      expect((await queue.counts('print')).failed, 1);
      expect(worker.failed, ['m1']);
    });

    test('defer requeues without consuming an attempt', () async {
      worker.handler = (_) async => const JobResult.defer('no session yet');
      final job = await queue.enqueue(kind: 'ai', mediaId: 'm1');
      final aiWorker = FakeWorker(queue: queue, kind: 'ai')
        ..handler = (_) async => const JobResult.defer();
      expect(await aiWorker.drain(), 0);

      final reloaded = await queue.findById(job.id);
      expect(reloaded!.status, PipelineJobStatus.pending);
      expect(reloaded.attempts, 0);
      expect(aiWorker.failed, isEmpty);
    });

    test('pause holds the whole kind rather than burning attempts', () async {
      worker.handler = (_) async => const JobResult.pause('ribbon out');
      for (var i = 0; i < 3; i++) {
        await queue.enqueue(kind: 'print', mediaId: 'm$i');
      }
      await worker.drain();

      final counts = await queue.counts('print');
      expect(counts.paused, 3, reason: 'every open job of the kind is held');
      expect(counts.failed, 0);
      expect(await queue.isKindPaused('print'), isTrue);

      // Reloading the printer resumes the queue with no restart.
      await queue.resumeKind('print');
      worker.handler = null;
      expect(await worker.drainUntilIdle(), 3);
    });

    test('a thrown error is classified, not swallowed', () async {
      worker.handler = (_) async => throw ApiException('nope', 400);
      await queue.enqueue(kind: 'print', mediaId: 'm1');
      await worker.drain();
      // 400 is not retryable, so this is terminal after a single attempt.
      final counts = await queue.counts('print');
      expect(counts.failed, 1);
      expect(worker.failed, ['m1']);
    });

    test('a thrown transient error retries instead of failing', () async {
      worker.handler = (_) async => throw ApiException('down', 503);
      await queue.enqueue(kind: 'print', mediaId: 'm1');
      await worker.drain();
      final counts = await queue.counts('print');
      expect(counts.failed, 0);
      expect(counts.pending, 1);
    });

    test('a drain that throws internally does not break the loop', () async {
      worker.handler = (_) async => throw StateError('boom');
      await queue.enqueue(kind: 'print', mediaId: 'm1');
      expect(await worker.drain(), 0);
      // StateError is treated as retryable, so the job survives for another go.
      expect((await queue.counts('print')).pending, 1);
    });
  });

  group('lifecycle', () {
    test('start is idempotent and stop halts the timer', () {
      expect(worker.isRunning, isFalse);
      worker.start(interval: const Duration(seconds: 30));
      expect(worker.isRunning, isTrue);
      worker.start(interval: const Duration(seconds: 30));
      expect(worker.isRunning, isTrue);
      worker.stop();
      expect(worker.isRunning, isFalse);
    });
  });
}
