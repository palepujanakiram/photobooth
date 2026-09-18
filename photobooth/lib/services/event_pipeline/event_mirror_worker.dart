import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../../models/event_pipeline/media_item.dart';
import '../../models/event_pipeline/pipeline_job.dart';
import '../../utils/event_bulk_import.dart';
import '../../utils/exceptions.dart';
import '../../utils/logger.dart';
import '../api_service.dart';
import '../kiosk_manager.dart';
import 'event_media_store.dart';
import 'event_pipeline_db.dart';
import 'event_pipeline_ledger.dart';
import 'event_pipeline_worker.dart';

/// Ordered stages of mirroring one item to the backend.
///
/// Order matters and is enforced: the AI step blocks on `remote_session_id`,
/// which only [session] produces, and an asset cannot be attached to a session
/// that does not exist.
abstract final class MirrorStage {
  /// Creates the server session and records `remote_session_id`.
  static const String session = 'session';

  /// Uploads the derivative and records `remote_photo_id`.
  static const String asset = 'asset';

  /// Mirrors stage changes for logging and future reprint.
  static const String row = 'row';

  static const List<String> order = <String>[session, asset, row];
}

/// Best-effort backend mirror for the event pipeline.
///
/// **Deliberately not `KioskOutboxWorker`.** That worker walks
/// `LocalMediaStore.listAll()` and enqueues every file it finds, which would
/// sweep in event media wholesale; it also prunes synced files after seven days,
/// which would destroy an event's reprintable copies. This has its own queue,
/// its own pacing, and touches only what it is given.
///
/// Nothing in the event flow blocks on this. With the pipeline offline it does
/// not run at all.
class EventMirrorWorker {
  EventMirrorWorker({
    required EventPipelineDb db,
    required EventPipelineLedger ledger,
    required bool Function() enabled,
    EventMediaStore? mediaStore,
    ApiService? api,
    KioskManager? kioskManager,
    int Function()? nowMs,
    String Function()? newId,
    this.batchLimit = 2,
  })  : _db = db.database,
        _ledger = ledger,
        _enabled = enabled,
        _media = mediaStore ?? EventMediaStore(),
        _api = api ?? ApiService(),
        _kiosk = kioskManager ?? KioskManager(),
        _nowMs = nowMs ?? _defaultNowMs,
        _newId = newId ?? _defaultNewId;

  final Database _db;
  final EventPipelineLedger _ledger;
  final bool Function() _enabled;
  final EventMediaStore _media;
  final ApiService _api;
  final KioskManager _kiosk;
  final int Function() _nowMs;
  final String Function() _newId;

  /// Small on purpose. A 3,000-frame event means 3,000 session creations, and
  /// bursting those would saturate a venue link mid-event.
  final int batchLimit;

  static int _defaultNowMs() => DateTime.now().millisecondsSinceEpoch;
  static int _idCounter = 0;
  static String _defaultNewId() =>
      'up-${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

  Timer? _timer;
  Future<void> _chain = Future<void>.value();

  bool get isRunning => _timer != null;

  void start({Duration interval = const Duration(seconds: 20)}) {
    if (_timer != null) return;
    unawaited(drain());
    _timer = Timer.periodic(interval, (_) => unawaited(drain()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Queues the full mirror chain for an item.
  Future<void> enqueueItem(String mediaId) async {
    for (final stage in MirrorStage.order) {
      await _enqueue(kind: stage, mediaId: mediaId);
    }
  }

  Future<void> _enqueue({
    required String kind,
    required String mediaId,
  }) async {
    final existing = await _find(kind: kind, mediaId: mediaId);
    if (existing != null) return;
    final now = _nowMs();
    try {
      await _db.insert('evp_upload_queue', <String, Object?>{
        'id': _newId(),
        'media_id': mediaId,
        'kind': kind,
        'payload_json': '{}',
        'status': PipelineJobStatus.pending,
        'attempts': 0,
        'next_attempt_at_ms': 0,
        'created_at_ms': now,
        'updated_at_ms': now,
      });
    } on DatabaseException catch (e) {
      if (!e.isUniqueConstraintError()) rethrow;
    }
  }

  Future<int> drain({int? limit}) {
    final done = Completer<int>();
    _chain = _chain.then((_) async {
      try {
        done.complete(await _drainUnlocked(limit ?? batchLimit));
      } catch (e, st) {
        AppLogger.error('EventMirrorWorker drain failed', error: e, stackTrace: st);
        done.complete(0);
      }
    });
    return done.future;
  }

  Future<int> drainUntilIdle({int maxRounds = 500}) async {
    var total = 0;
    for (var round = 0; round < maxRounds; round++) {
      final n = await drain();
      if (n == 0) break;
      total += n;
    }
    return total;
  }

  Future<int> _drainUnlocked(int limit) async {
    if (!_enabled()) return 0;
    final kioskCode = (await _kiosk.getKioskCode())?.trim().toUpperCase();
    if (kioskCode == null || kioskCode.isEmpty) return 0;

    var completed = 0;
    // Stage order is enforced by draining stage by stage: an asset is never
    // attempted before its session exists.
    for (final stage in MirrorStage.order) {
      final rows = await _claimReady(stage, limit);
      for (final row in rows) {
        if (await _runOne(kioskCode, row)) completed++;
      }
    }
    return completed;
  }

  Future<List<Map<String, Object?>>> _claimReady(String kind, int limit) async {
    final now = _nowMs();
    final rows = await _db.query(
      'evp_upload_queue',
      where: 'kind = ? AND status = ? AND next_attempt_at_ms <= ?',
      whereArgs: [kind, PipelineJobStatus.pending, now],
      orderBy: 'created_at_ms ASC',
      limit: limit,
    );
    final claimed = <Map<String, Object?>>[];
    for (final row in rows) {
      final n = await _db.update(
        'evp_upload_queue',
        <String, Object?>{
          'status': PipelineJobStatus.claimed,
          'updated_at_ms': now,
        },
        where: 'id = ? AND status = ?',
        whereArgs: [row['id'], PipelineJobStatus.pending],
      );
      if (n == 1) claimed.add(row);
    }
    return claimed;
  }

  Future<bool> _runOne(String kioskCode, Map<String, Object?> row) async {
    final id = (row['id'] ?? '').toString();
    final kind = (row['kind'] ?? '').toString();
    final mediaId = (row['media_id'] ?? '').toString();
    try {
      final outcome = await _dispatch(kioskCode, kind, mediaId);
      switch (outcome) {
        case _MirrorOutcome.done:
          await _markDone(id);
          return true;
        case _MirrorOutcome.defer:
          await _defer(id);
          return false;
        case _MirrorOutcome.drop:
          // Nothing to mirror and never will be — a media item deleted under us.
          await _markDone(id);
          return false;
      }
    } catch (e, st) {
      AppLogger.warning('Mirror $kind failed for $mediaId', error: e, stackTrace: st);
      await _markFailed(id, e);
      return false;
    }
  }

  Future<_MirrorOutcome> _dispatch(
    String kioskCode,
    String kind,
    String mediaId,
  ) async {
    final item = await _ledger.findById(mediaId);
    if (item == null) return _MirrorOutcome.drop;
    switch (kind) {
      case MirrorStage.session:
        return _mirrorSession(kioskCode, item);
      case MirrorStage.asset:
        return _mirrorAsset(kioskCode, item);
      case MirrorStage.row:
        return _mirrorRow(kioskCode, item);
      default:
        return _MirrorOutcome.drop;
    }
  }

  /// Creates one server session per photo, auto-accepting terms.
  ///
  /// The host accepted the event's terms, so every photo accepts on their
  /// behalf — the same call `_importOnePhoto` makes today for card imports.
  Future<_MirrorOutcome> _mirrorSession(String kioskCode, MediaItem item) async {
    if ((item.remoteSessionId?.trim().isNotEmpty ?? false)) {
      return _MirrorOutcome.done;
    }
    final response = await _api.acceptTermsAndCreateSession(
      kioskCode: kioskCode,
      source: _sourceLabel(item.source),
      groupConsentAccepted: true,
    );
    final sessionId = eventSessionIdFromCreateResponse(response);
    if (sessionId == null) {
      throw ApiException('Session create returned no id');
    }
    await _ledger.setRemoteIds(item.id, sessionId: sessionId);
    return _MirrorOutcome.done;
  }

  /// Uploads the derivative and attaches it to the session.
  Future<_MirrorOutcome> _mirrorAsset(String kioskCode, MediaItem item) async {
    final sessionId = item.remoteSessionId?.trim() ?? '';
    // Stage order should prevent this, but a manual requeue could reach here.
    if (sessionId.isEmpty) return _MirrorOutcome.defer;
    if ((item.remotePhotoId?.trim().isNotEmpty ?? false)) {
      return _MirrorOutcome.done;
    }

    final rendition = await _ledger.bestRenditionForPrint(item.id);
    if (rendition == null) return _MirrorOutcome.defer;
    final file = await _media.getFile(rendition.path);
    if (file == null) return _MirrorOutcome.defer;

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return _MirrorOutcome.defer;

    await _api.ingestKioskAsset(
      kioskCode: kioskCode,
      prefix: 'event-originals',
      filename: '${item.id}.jpg',
      bytes: bytes,
    );
    // The session's photo id is what AI generation keys on; attaching the image
    // is what makes it exist.
    await _api.updateSession(
      sessionId: sessionId,
      userImageUrl: eventImportBytesToDataUrl(bytes, 'image/jpeg'),
    );
    await _ledger.setRemoteIds(item.id, photoId: item.id);
    return _MirrorOutcome.done;
  }

  /// Mirrors the item's stage for server-side logging and future reprint.
  Future<_MirrorOutcome> _mirrorRow(String kioskCode, MediaItem item) async {
    await _api.ingestKioskEntities(
      kioskCode: kioskCode,
      items: <Map<String, dynamic>>[
        <String, dynamic>{
          'entityType': 'event_media_item',
          'entityId': item.id,
          'payload': <String, dynamic>{
            'eventId': item.eventId,
            'sessionId': item.remoteSessionId,
            'stage': item.stage,
            'source': item.source,
            'originalFilename': item.originalFilename,
            'capturedAtMs': item.capturedAtMs,
            'aiSkipped': item.aiSkipped,
          },
        },
      ],
    );
    return _MirrorOutcome.done;
  }

  static String _sourceLabel(String source) {
    switch (source) {
      case MediaSource.sdCard:
      case MediaSource.folder:
        return kEventSdImportSource;
      case MediaSource.gallery:
        return 'event-gallery';
      default:
        return 'event-capture';
    }
  }

  Future<void> _markDone(String id) async {
    await _db.update(
      'evp_upload_queue',
      <String, Object?>{
        'status': PipelineJobStatus.done,
        'last_error': null,
        'updated_at_ms': _nowMs(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Requeues without counting an attempt — the item is not ready, not broken.
  Future<void> _defer(String id) async {
    final now = _nowMs();
    await _db.update(
      'evp_upload_queue',
      <String, Object?>{
        'status': PipelineJobStatus.pending,
        'next_attempt_at_ms': now + const Duration(seconds: 30).inMilliseconds,
        'updated_at_ms': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> _markFailed(String id, Object error) async {
    final rows = await _db.query(
      'evp_upload_queue',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final attempts = ((rows.first['attempts'] as int?) ?? 0) + 1;
    final now = _nowMs();
    final exhausted = !isRetryableEventError(error) ||
        PipelineBackoff.isExhausted(attempts);
    await _db.update(
      'evp_upload_queue',
      <String, Object?>{
        'status':
            exhausted ? PipelineJobStatus.failed : PipelineJobStatus.pending,
        'attempts': attempts,
        'next_attempt_at_ms':
            exhausted ? 0 : PipelineBackoff.nextAttemptAt(now, attempts),
        'last_error': error.toString(),
        'updated_at_ms': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, Object?>?> _find({
    required String kind,
    required String mediaId,
  }) async {
    final rows = await _db.query(
      'evp_upload_queue',
      where: 'kind = ? AND media_id = ?',
      whereArgs: [kind, mediaId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Open/done/failed tallies across every mirror stage.
  Future<Map<String, int>> counts() async {
    final rows = await _db.rawQuery(
      'SELECT status, COUNT(*) AS n FROM evp_upload_queue GROUP BY status',
    );
    return {
      for (final r in rows)
        (r['status'] ?? '').toString(): (r['n'] as int?) ?? 0,
    };
  }
}

enum _MirrorOutcome { done, defer, drop }
