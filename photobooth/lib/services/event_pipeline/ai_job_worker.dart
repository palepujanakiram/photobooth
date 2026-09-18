import '../../models/event_pipeline/event_pipeline_settings.dart';
import '../../models/event_pipeline/media_item.dart';
import '../../models/event_pipeline/media_rendition.dart';
import '../../models/event_pipeline/pipeline_job.dart';
import '../../utils/exceptions.dart';
import '../api_service.dart';
import '../kiosk_manager.dart';
import 'event_media_store.dart';
import 'event_pipeline_ledger.dart';
import 'event_pipeline_queue.dart';
import 'event_pipeline_worker.dart';

/// Fetches the bytes of a generated image. Injected so the worker is testable
/// without a network, and so the auth-aware loader stays in one place.
typedef AiImageFetch = Future<List<int>> Function(String url);

/// Drains `ai` jobs against the server generation endpoint.
///
/// **The only stage that needs WAN.** It is never scheduled for an event with
/// AI off, and when the link is down its jobs wait rather than fail — an event
/// whose internet never returns is rescued by the operator's **Skip AI** action,
/// not by the queue giving up.
class AiJobWorker extends EventPipelineWorker {
  AiJobWorker({
    required super.queue,
    required EventPipelineLedger ledger,
    required EventMediaStore mediaStore,
    required EventPipelineSettings Function() settings,
    ApiService? api,
    AiImageFetch? fetchImage,
    KioskManager? kioskManager,
    super.batchLimit = 2,
    int Function()? nowMs,
  })  : _ledger = ledger,
        _media = mediaStore,
        _settings = settings,
        _api = api ?? ApiService(),
        _fetchImage = fetchImage,
        _kiosk = kioskManager ?? KioskManager(),
        _nowMs = nowMs ?? _defaultNowMs,
        super(kind: EventPipelineStep.ai);

  final EventPipelineLedger _ledger;
  final EventMediaStore _media;
  final EventPipelineSettings Function() _settings;
  final ApiService _api;
  final AiImageFetch? _fetchImage;
  final KioskManager _kiosk;
  final int Function() _nowMs;

  static int _defaultNowMs() => DateTime.now().millisecondsSinceEpoch;

  /// Short: the mirror is actively working and may land within seconds.
  static const Duration _mirrorWait = Duration(seconds: 10);

  @override
  Future<JobResult> process(PipelineJob job) async {
    final item = await _ledger.findById(job.mediaId);
    if (item == null) {
      return const JobResult.fail('Media item no longer exists');
    }

    final settings = _settings();
    if (settings.offlineMode) {
      // Deliberate: an offline event's AI jobs sit in the queue rather than
      // burning attempts against a link that is not coming back this session.
      return const JobResult.defer(
        'Event is in offline mode',
        Duration(minutes: 10),
      );
    }

    // The kiosk-level toggle is separate from the event's `aiEnabled`, and it
    // wins: an operator who turned FotoZen AI off on this device expects no
    // generation regardless of what the event asks for.
    if (!await _kiosk.isAiPhotosEnabled()) {
      return const JobResult.defer(
        'FotoZen AI is turned off on this kiosk',
        Duration(minutes: 10),
      );
    }

    final themeId = settings.themeId;
    if (themeId == null || themeId.trim().isEmpty) {
      // A single event theme is the design; without one there is nothing to
      // generate under, and retrying will not conjure one.
      return const JobResult.fail('No event theme configured');
    }

    final gate = _mirrorGate(item);
    if (gate != null) return gate;

    return _generate(item, themeId: themeId, attempt: job.attempts + 1);
  }

  /// The ordering dependency: generation needs a server session.
  ///
  /// `ApiService.generateImages` takes a `sessionId` and `originalPhotoId`, both
  /// produced by the mirror's `session` and `asset` steps. Until those land the
  /// job **defers** — it is waiting on another worker, which is not a failure
  /// and must not consume its retry budget.
  JobResult? _mirrorGate(MediaItem item) {
    final sessionId = item.remoteSessionId?.trim() ?? '';
    if (sessionId.isEmpty) {
      return const JobResult.defer(
        'Waiting for the server session',
        _mirrorWait,
      );
    }
    final photoId = item.remotePhotoId?.trim() ?? '';
    if (photoId.isEmpty) {
      return const JobResult.defer(
        'Waiting for the photo upload',
        _mirrorWait,
      );
    }
    return null;
  }

  Future<JobResult> _generate(
    MediaItem item, {
    required String themeId,
    required int attempt,
  }) async {
    try {
      final result = await _api.generateImages(
        sessionId: item.remoteSessionId!,
        // One image per photo. The guest flow generates several so a person can
        // choose; here there is nobody choosing, and every extra slot is spend.
        count: 1,
        attempt: attempt,
        originalPhotoId: item.remotePhotoId!,
        themeId: themeId,
      );

      final url = result.preferredImageUrl;
      if (url == null || url.isEmpty) {
        return const JobResult.retry('Generation returned no image');
      }
      return await _storeResult(item, url);
    } on ApiException catch (e) {
      return isRetryableEventError(e)
          ? JobResult.retry(e.message)
          : JobResult.fail(e.message);
    } catch (e) {
      return JobResult.retry(e.toString());
    }
  }

  Future<JobResult> _storeResult(MediaItem item, String url) async {
    final bytes = await _download(url);
    if (bytes.isEmpty) {
      return const JobResult.retry('Generated image could not be downloaded');
    }

    final path = EventMediaStore.relativePathFor(
      mediaId: item.id,
      kind: RenditionKind.ai,
      eventId: item.eventId,
    );
    final written = await _media.putBytes(path, bytes);
    if (written == null) {
      return const JobResult.retry('Could not store the generated image');
    }

    await _ledger.putRendition(MediaRendition(
      mediaId: item.id,
      kind: RenditionKind.ai,
      path: path,
      bytes: bytes.length,
      createdAtMs: _nowMs(),
    ));
    return const JobResult.done();
  }

  Future<List<int>> _download(String url) async {
    final fetch = _fetchImage;
    if (fetch != null) return fetch(url);
    final file = await _api.downloadImageToTemp(url);
    return file.readAsBytes();
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
    // The source derivative is still printable, so a failed generation costs the
    // styling, not the photograph.
    await _ledger.setStage(job.mediaId, MediaStage.failed, error: error);
  }
}

/// Rewrites stuck items to skip AI — the operator's way out of a dead link.
///
/// The **only** sanctioned rewrite of a frozen step list, and it is safe for the
/// same reason freezing was: this is an explicit, logged operator action rather
/// than settings drift leaking into work already in flight.
class SkipAiAction {
  const SkipAiAction({
    required EventPipelineLedger ledger,
    required EventPipelineQueue queue,
  })  : _ledger = ledger,
        _queue = queue;

  final EventPipelineLedger _ledger;
  final EventPipelineQueue _queue;

  /// Drops `ai` from each item's chain, cancels its queued AI job, and enqueues
  /// whatever step the item now sits on.
  ///
  /// Returns how many items were changed.
  Future<int> apply(Iterable<String> mediaIds) async {
    var changed = 0;
    for (final mediaId in mediaIds) {
      final item = await _ledger.findById(mediaId);
      if (item == null) continue;

      final newSteps = EventPipelineSettings.withoutAi(item.steps);
      final updated = await _ledger.skipAi(mediaId, newSteps: newSteps);
      if (updated == null) continue;
      changed++;

      await _queue.cancelFor(kind: EventPipelineStep.ai, mediaId: mediaId);

      final next = updated.currentStep;
      if (next != null) {
        await _queue.enqueue(
          kind: next,
          mediaId: mediaId,
          eventId: updated.eventId,
        );
      }
    }
    return changed;
  }
}
