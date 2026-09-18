import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/event_pipeline/event_pipeline_settings.dart';
import '../../models/event_pipeline/media_item.dart';
import '../../models/event_pipeline/pipeline_job.dart';
import '../../models/event_pipeline/printer_consumables.dart';
import 'event_media_store.dart';
import 'event_pipeline_ledger.dart';
import 'event_pipeline_worker.dart';
import 'printer_status_reader.dart';

/// Sends one image to the printer.
///
/// Injected rather than calling `PrintService` directly so the worker is
/// testable without a printer, and so the Selphy/DNP fan-out stays in one place.
typedef EventPrintFn = Future<void> Function(
  XFile imageFile, {
  required String printSize,
  int quantity,
});

/// Drains `print` jobs against the local ledger.
///
/// **The first time a failed print is persisted and retried.** Today
/// `recordPrintJob` is called only after success with a hardcoded `'COMPLETED'`
/// (`local_kiosk_settlement.dart:98`), so a failure is logged and lost on
/// restart.
class PrintJobWorker extends EventPipelineWorker {
  PrintJobWorker({
    required super.queue,
    required EventPipelineLedger ledger,
    required EventMediaStore mediaStore,
    required EventPrintFn printFn,
    required EventPipelineSettings Function() settings,
    PrinterStatusReader? statusReader,
    super.batchLimit = 1,
  })  : _ledger = ledger,
        _media = mediaStore,
        _print = printFn,
        _settings = settings,
        _status = statusReader ?? PrinterStatusReader(),
        super(kind: EventPipelineStep.print);

  final EventPipelineLedger _ledger;
  final EventMediaStore _media;
  final EventPrintFn _print;
  final EventPipelineSettings Function() _settings;
  final PrinterStatusReader _status;

  /// A USB print that never returns would leave the job `CLAIMED` forever.
  @visibleForTesting
  Duration printTimeout = const Duration(minutes: 2);

  @override
  Future<JobResult> process(PipelineJob job) async {
    final item = await _ledger.findById(job.mediaId);
    if (item == null) {
      return const JobResult.fail('Media item no longer exists');
    }

    // Best available: framed, else the AI result, else the source derivative.
    // So a failed frame or AI step still produces a print rather than nothing.
    final rendition = await _ledger.bestRenditionForPrint(item.id);
    if (rendition == null) {
      return const JobResult.fail('No stored image to print');
    }
    final file = await _media.getFile(rendition.path);
    if (file == null) {
      return const JobResult.fail('Stored image is missing from disk');
    }

    final consumables = await _status.read();
    final gate = _gateOn(consumables);
    if (gate != null) return gate;

    final settings = _settings();
    final copies = _copiesFor(job, settings);
    try {
      await _print(
        XFile(file.path, mimeType: 'image/jpeg'),
        printSize: settings.printSize,
        quantity: copies,
      ).timeout(printTimeout);
      return const JobResult.done();
    } catch (e) {
      // Re-read status: a mid-job failure is very often the media running out,
      // and that must pause the queue rather than consume this job's attempts.
      final after = await _status.read();
      if (after.shouldPause) return JobResult.pause(after.reason);
      return JobResult.retry(e.toString());
    }
  }

  /// Turns a pre-flight status reading into a queue action.
  JobResult? _gateOn(PrinterConsumables consumables) {
    switch (consumables.readiness) {
      case PrinterReadiness.ready:
        return null;
      case PrinterReadiness.busy:
        // Cooling or standby clears itself; wait without spending an attempt.
        return JobResult.defer(consumables.reason);
      case PrinterReadiness.needsAttention:
        return JobResult.pause(consumables.reason);
      case PrinterReadiness.badJob:
        return JobResult.fail(consumables.reason);
      case PrinterReadiness.offline:
        // No printer yet is a waiting state, not a failure — the reader may be
        // plugged in later, and an offline event should not lose its queue.
        return JobResult.defer(consumables.reason);
      case PrinterReadiness.needsPermission:
        // The printer is there but unopened. Waiting rather than failing for
        // the same reason: an operator tapping Allow on the hub should find
        // the queue intact and draining, not a wall of failed prints.
        return JobResult.defer(consumables.reason);
    }
  }

  /// Copies come from the job payload when present, so a batch keeps the count
  /// it was queued with even if settings change afterwards.
  static int _copiesFor(PipelineJob job, EventPipelineSettings settings) {
    final raw = job.payload['copies'];
    final fromPayload = raw is int ? raw : (raw is num ? raw.toInt() : null);
    final copies = fromPayload ?? settings.defaultCopies;
    return copies < 1 ? 1 : copies;
  }

  @override
  Future<void> onJobDone(PipelineJob job) async {
    final advanced = await _ledger.advanceStep(job.mediaId);
    final next = advanced?.currentStep;
    if (next == null) return;
    await queue.enqueue(
      kind: next,
      mediaId: job.mediaId,
      eventId: advanced?.eventId,
    );
  }

  @override
  Future<void> onJobFailed(PipelineJob job, String error) async {
    await _ledger.setStage(job.mediaId, MediaStage.failed, error: error);
  }
}
