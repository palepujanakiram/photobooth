import '../../models/event_pipeline/event_pipeline_settings.dart';
import '../../models/event_pipeline/event_print_size.dart';
import '../../models/event_pipeline/media_item.dart';
import '../../models/event_pipeline/media_rendition.dart';
import '../../models/event_pipeline/pipeline_job.dart';
import '../../utils/logger.dart';
import 'event_frame_cache.dart';
import 'event_media_store.dart';
import 'event_pipeline_ledger.dart';
import 'event_pipeline_worker.dart';
import 'frame_compositor.dart';

/// Drains `frame` jobs, compositing each item onto the print raster.
///
/// Fully local — no WAN, which is what makes an AI-off event complete offline.
class FrameJobWorker extends EventPipelineWorker {
  FrameJobWorker({
    required super.queue,
    required EventPipelineLedger ledger,
    required EventFrameCache frameCache,
    required EventMediaStore mediaStore,
    required FrameCompositor compositor,
    required EventPipelineSettings Function() settings,
    super.batchLimit,
    int Function()? nowMs,
  })  : _ledger = ledger,
        _frames = frameCache,
        _media = mediaStore,
        _compositor = compositor,
        _settings = settings,
        _nowMs = nowMs ?? _defaultNowMs,
        super(kind: EventPipelineStep.frame);

  final EventPipelineLedger _ledger;
  final EventFrameCache _frames;
  final EventMediaStore _media;
  final FrameCompositor _compositor;
  final EventPipelineSettings Function() _settings;
  final int Function() _nowMs;

  static int _defaultNowMs() => DateTime.now().millisecondsSinceEpoch;

  @override
  Future<JobResult> process(PipelineJob job) async {
    final item = await _ledger.findById(job.mediaId);
    if (item == null) {
      return const JobResult.fail('Media item no longer exists');
    }

    // Framing runs on the best rendition available, so an AI result is framed
    // when there is one and the source derivative otherwise.
    final input = await _ledger.bestRenditionForPrint(item.id);
    if (input == null) {
      return const JobResult.fail('No stored image to frame');
    }
    final inputFile = await _media.getFile(input.path);
    if (inputFile == null) {
      return const JobResult.fail('Stored image is missing from disk');
    }

    final settings = _settings();
    final frameId = settings.frameId;
    if (frameId == null || frameId.trim().isEmpty) {
      return const JobResult.fail('No frame configured for this event');
    }

    final framePath = await _frames.localFilePath(frameId);
    if (framePath == null) {
      // Not the job's fault and not permanent — the frame may still be
      // downloading, or WAN may return. Waiting must not consume attempts.
      return const JobResult.defer('Frame overlay not cached yet');
    }

    try {
      final size = EventPrintSize.fromToken(settings.printSize);
      final result = await _compositor.composite(
        photoPath: inputFile.path,
        framePath: framePath,
        size: size,
        // Second encode off the finished canvas, so the queue grid shows the
        // framed result rather than the raw import. One decode, two encodes.
        thumbShortSide: RenditionKind.thumbShortSide,
      );

      final path = EventMediaStore.relativePathFor(
        mediaId: item.id,
        kind: RenditionKind.framed,
        eventId: item.eventId,
      );
      final written = await _media.putBytes(path, result.bytes);
      if (written == null) {
        return const JobResult.retry('Could not write the framed image');
      }

      await _ledger.putRendition(MediaRendition(
        mediaId: item.id,
        kind: RenditionKind.framed,
        path: path,
        width: result.width,
        height: result.height,
        bytes: result.bytes.length,
        createdAtMs: _nowMs(),
      ));
      await _overwriteThumb(item, result);
      return const JobResult.done();
    } catch (e) {
      // A decode failure on one photo is that photo's problem; the queue keeps
      // going and print still falls back to the AI or source rendition.
      return JobResult.retry(e.toString());
    }
  }

  /// Replaces the import-time thumbnail with the framed one.
  ///
  /// The grid always shows current state, so a photo that has been framed must
  /// stop looking like one that has not. Best effort — a stale thumbnail is a
  /// cosmetic problem, and failing a finished frame job over it is not.
  Future<void> _overwriteThumb(MediaItem item, CompositeResult result) async {
    final bytes = result.thumbBytes;
    if (bytes == null || bytes.isEmpty) return;
    final path = EventMediaStore.relativePathFor(
      mediaId: item.id,
      kind: RenditionKind.thumb,
      eventId: item.eventId,
    );
    try {
      if (await _media.putBytes(path, bytes) == null) return;
      await _ledger.putRendition(MediaRendition(
        mediaId: item.id,
        kind: RenditionKind.thumb,
        path: path,
        width: result.thumbWidth,
        height: result.thumbHeight,
        bytes: bytes.length,
        createdAtMs: _nowMs(),
      ));
    } catch (e) {
      AppLogger.debug('Thumbnail overwrite failed for ${item.id}: $e');
    }
  }

  /// Advances the item to its next step and enqueues that job.
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
    // The item is not dead: print resolves framed → ai → source, so it can still
    // produce a print from what it already has. Only the stage records the fault.
    await _ledger.setStage(job.mediaId, MediaStage.failed, error: error);
  }
}
