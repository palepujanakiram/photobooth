import 'package:sqflite/sqflite.dart';

import '../../models/event_pipeline/event_frame.dart';
import '../../models/kiosk_frame_model.dart';
import '../../utils/logger.dart';
import '../../utils/secure_image_url.dart';
import '../api_service.dart';
import '../local_guest_media_write.dart';
import 'event_media_store.dart';
import 'event_pipeline_db.dart';

/// Downloads and stores an event's frame overlays so framing can run offline.
///
/// `ApiService.getKioskFrames()` already accepts an `eventCode` and disk-caches
/// the frame **metadata** per kiosk+event. What was missing — and what this adds
/// — is the overlay **bytes**. Without them a frame-enabled event that loses its
/// link cannot complete a single item.
class EventFrameCache {
  EventFrameCache({
    required EventPipelineDb db,
    EventMediaStore? mediaStore,
    ApiService? api,
    Future<List<int>> Function(String url)? fetchBytes,
    int Function()? nowMs,
  })  : _db = db.database,
        _media = mediaStore ?? EventMediaStore(),
        _api = api ?? ApiService(),
        _fetchBytes = fetchBytes ?? guestMediaNetworkFetch(),
        _nowMs = nowMs ?? _defaultNowMs;

  final Database _db;
  final EventMediaStore _media;
  final ApiService _api;
  final Future<List<int>> Function(String url) _fetchBytes;
  final int Function() _nowMs;

  static int _defaultNowMs() => DateTime.now().millisecondsSinceEpoch;

  static String relativePathFor({
    required String eventId,
    required String frameId,
  }) {
    return EventMediaStore.relativePathFor(
      mediaId: 'frame-$frameId',
      kind: 'overlay',
      eventId: eventId,
    );
  }

  /// Fetches the catalogue and downloads any overlay not already on disk.
  ///
  /// Needs WAN, so it belongs in event setup rather than mid-import. Returns the
  /// resulting status, which the station shows so an operator can see whether
  /// framing will work before the link is gone.
  Future<FrameCacheStatus> refresh({
    required String eventId,
    String? selectedFrameId,
  }) async {
    List<KioskFrameModel> frames;
    try {
      frames = await _api.getKioskFrames();
    } catch (e, st) {
      AppLogger.warning(
        'Frame catalogue fetch failed; using what is already cached',
        error: e,
        stackTrace: st,
      );
      return status(eventId: eventId, selectedFrameId: selectedFrameId);
    }

    for (final frame in frames) {
      if (frame.id.isEmpty || frame.overlayUrl.isEmpty) continue;
      await _upsertMetadata(eventId, frame);
      await _downloadIfMissing(eventId, frame.id);
    }
    return status(eventId: eventId, selectedFrameId: selectedFrameId);
  }

  Future<void> _upsertMetadata(String eventId, KioskFrameModel frame) async {
    final existing = await findById(frame.id);
    // Preserve local_path so a metadata refresh does not orphan a downloaded
    // overlay and force it to be fetched again.
    await _db.insert(
      'evp_event_frames',
      EventFrame(
        id: frame.id,
        eventId: eventId,
        overlayUrl: frame.overlayUrl,
        name: frame.name,
        localPath: existing?.overlayUrl == frame.overlayUrl
            ? existing?.localPath
            : null,
        width: existing?.width,
        height: existing?.height,
        downloadedAtMs: existing?.downloadedAtMs,
      ).toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> _downloadIfMissing(String eventId, String frameId) async {
    final frame = await findById(frameId);
    if (frame == null) return false;
    if (frame.isCached && await _media.getFile(frame.localPath!) != null) {
      return true;
    }
    return download(frame);
  }

  /// Fetches one overlay's bytes and records where they landed.
  Future<bool> download(EventFrame frame) async {
    try {
      final url = SecureImageUrl.absolutize(frame.overlayUrl);
      final bytes = await _fetchBytes(url);
      if (bytes.isEmpty) return false;

      final path = relativePathFor(
        eventId: frame.eventId,
        frameId: frame.id,
      );
      final file = await _media.putBytes(path, bytes);
      if (file == null) return false;

      await _db.update(
        'evp_event_frames',
        <String, Object?>{
          'local_path': path,
          'downloaded_at_ms': _nowMs(),
        },
        where: 'id = ?',
        whereArgs: [frame.id],
      );
      return true;
    } catch (e, st) {
      AppLogger.warning(
        'Frame overlay download failed for ${frame.id}',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }

  Future<EventFrame?> findById(String frameId) async {
    final rows = await _db.query(
      'evp_event_frames',
      where: 'id = ?',
      whereArgs: [frameId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return EventFrame.fromRow(rows.first);
  }

  Future<List<EventFrame>> listForEvent(String eventId) async {
    final rows = await _db.query(
      'evp_event_frames',
      where: 'event_id = ?',
      whereArgs: [eventId],
      orderBy: 'name ASC',
    );
    return [for (final r in rows) EventFrame.fromRow(r)];
  }

  /// The absolute file for a frame, or null when it has not been downloaded.
  Future<String?> localFilePath(String frameId) async {
    final frame = await findById(frameId);
    final path = frame?.localPath;
    if (path == null) return null;
    final file = await _media.getFile(path);
    return file?.path;
  }

  /// Whether framing can run right now, and for the configured frame in particular.
  Future<FrameCacheStatus> status({
    required String eventId,
    String? selectedFrameId,
  }) async {
    final frames = await listForEvent(eventId);
    var cached = 0;
    var selectedCached = false;
    for (final frame in frames) {
      if (!frame.isCached) continue;
      if (await _media.getFile(frame.localPath!) == null) continue;
      cached++;
      if (frame.id == selectedFrameId) selectedCached = true;
    }
    return FrameCacheStatus(
      total: frames.length,
      cached: cached,
      selectedIsCached: selectedCached,
    );
  }
}
