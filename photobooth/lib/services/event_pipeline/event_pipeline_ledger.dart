import 'package:sqflite/sqflite.dart';

import '../../models/event_pipeline/media_item.dart';
import '../../models/event_pipeline/media_rendition.dart';
import 'event_pipeline_db.dart';

/// Result of trying to record a newly seen image.
class MediaInsertResult {
  const MediaInsertResult({required this.item, required this.isNew});

  final MediaItem item;

  /// False when the image was already in the ledger, by either dedupe tier.
  final bool isNew;
}

/// Row-level access to `evp_media_items` and `evp_media_renditions`.
///
/// Direct SQL on purpose. `LocalKioskStore` keeps its whole ledger in RAM and
/// calls `replaceAll()` on every mutation, which deletes and re-inserts every
/// row of every table — fine for 40 sessions a day, fatal at 3,000 photos.
class EventPipelineLedger {
  EventPipelineLedger({
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
      'mi-${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

  // ------------------------------------------------------------------ dedupe

  /// Records an image unless either dedupe tier already knows it.
  ///
  /// Tier 1 is `(source, sourceRef)` — path, size and mtime — which a rescan of
  /// a known card matches with no file read at all. Tier 2 is [contentKey],
  /// which catches the same photo arriving by a different route.
  Future<MediaInsertResult> insertIfNew({
    required String source,
    required String sourceRef,
    required String contentKey,
    String? eventId,
    String? originalFilename,
    int? capturedAtMs,
    int? originalBytes,
  }) async {
    final existing = await findByDedupeKeys(
      source: source,
      sourceRef: sourceRef,
      contentKey: contentKey,
    );
    if (existing != null) {
      return MediaInsertResult(item: existing, isNew: false);
    }

    final now = _nowMs();
    final item = MediaItem(
      id: _newId(),
      eventId: eventId,
      source: source,
      sourceRef: sourceRef,
      contentKey: contentKey,
      originalFilename: originalFilename,
      capturedAtMs: capturedAtMs,
      originalBytes: originalBytes,
      stage: MediaStage.ingested,
      createdAtMs: now,
      updatedAtMs: now,
    );
    try {
      await _db.insert('evp_media_items', item.toRow());
      return MediaInsertResult(item: item, isNew: true);
    } on DatabaseException catch (e) {
      // Two importers racing on the same card land here. The unique indexes are
      // the real guard; re-reading is how we return the winner's row.
      if (!e.isUniqueConstraintError()) rethrow;
      final winner = await findByDedupeKeys(
        source: source,
        sourceRef: sourceRef,
        contentKey: contentKey,
      );
      if (winner == null) rethrow;
      return MediaInsertResult(item: winner, isNew: false);
    }
  }

  Future<MediaItem?> findByDedupeKeys({
    required String source,
    required String sourceRef,
    required String contentKey,
  }) async {
    final rows = await _db.query(
      'evp_media_items',
      where: '(source = ? AND source_ref = ?) OR content_key = ?',
      whereArgs: [source, sourceRef, contentKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return MediaItem.fromRow(rows.first);
  }

  /// Tier-1 keys already present for [source], for diffing a scan in one pass.
  Future<Set<String>> knownSourceRefs(String source) async {
    final rows = await _db.query(
      'evp_media_items',
      columns: ['source_ref'],
      where: 'source = ?',
      whereArgs: [source],
    );
    return {for (final r in rows) (r['source_ref'] ?? '').toString()};
  }

  // -------------------------------------------------------------------- reads

  Future<MediaItem?> findById(String id) async {
    final rows = await _db.query(
      'evp_media_items',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return MediaItem.fromRow(rows.first);
  }

  Future<List<MediaItem>> listByStage(
    String stage, {
    int? limit,
    String? eventId,
  }) async {
    final scope = _eventScope(eventId);
    final rows = await _db.query(
      'evp_media_items',
      where: 'stage = ?${scope.clause}',
      whereArgs: [stage, ...scope.args],
      orderBy: 'created_at_ms ASC',
      limit: limit,
    );
    return [for (final r in rows) MediaItem.fromRow(r)];
  }

  /// One page of the queue, newest first within each stage.
  ///
  /// Ordered by how urgent a stage is to the operator rather than by time
  /// alone: failures first, then work in flight, then what is finished. A
  /// single ordered query rather than one per stage, so pagination is a real
  /// offset instead of seven interleaved limits.
  Future<List<MediaItem>> listPage({
    required int limit,
    int offset = 0,
    String? eventId,
    String? stage,
    List<String>? stages,
  }) async {
    final scope = _eventScope(eventId);
    final where = StringBuffer('1 = 1${scope.clause}');
    final args = <Object?>[...scope.args];
    if (stage != null) {
      where.write(' AND stage = ?');
      args.add(stage);
    } else if (stages != null && stages.isNotEmpty) {
      where.write(' AND stage IN (${List.filled(stages.length, '?').join(',')})');
      args.addAll(stages);
    }
    final rows = await _db.query(
      'evp_media_items',
      where: where.toString(),
      whereArgs: args,
      orderBy: '$_stageRank, created_at_ms DESC',
      limit: limit,
      offset: offset,
    );
    return [for (final r in rows) MediaItem.fromRow(r)];
  }

  /// How many items the current scope holds, for "load more" to know when to
  /// stop offering itself.
  Future<int> countItems({
    String? eventId,
    String? stage,
    List<String>? stages,
  }) async {
    final scope = _eventScope(eventId);
    final where = StringBuffer('1 = 1${scope.clause}');
    final args = <Object?>[...scope.args];
    if (stage != null) {
      where.write(' AND stage = ?');
      args.add(stage);
    } else if (stages != null && stages.isNotEmpty) {
      where.write(' AND stage IN (${List.filled(stages.length, '?').join(',')})');
      args.addAll(stages);
    }
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM evp_media_items WHERE ${where.toString()}',
      args,
    );
    return (rows.first['n'] as int?) ?? 0;
  }

  /// Stage ordering for the queue grid: what is wrong, then what is working,
  /// then what is done.
  static const String _stageRank = '''
CASE stage
  WHEN 'FAILED' THEN 0
  WHEN 'PRINTING' THEN 1
  WHEN 'FRAMING' THEN 2
  WHEN 'AI' THEN 3
  WHEN 'QUEUED' THEN 4
  WHEN 'INGESTED' THEN 5
  ELSE 6
END''';

  /// Scopes a read to one event.
  ///
  /// The ledger is durable across events, so an unscoped read at a wedding
  /// would mix in last weekend's corporate party — wrong counts, and a real
  /// chance of reprinting the wrong couple's photos (spec §9B). A null
  /// [eventId] means the **unassigned** rows, not "everything": items imported
  /// before an event was bound are shown only under their own filter, never
  /// folded into an event's totals.
  _EventScope _eventScope(String? eventId) {
    final id = eventId?.trim() ?? '';
    if (id.isEmpty) return const _EventScope(' AND event_id IS NULL', []);
    return _EventScope(' AND event_id = ?', [id]);
  }

  /// Imported but not yet selected — what the review grid shows.
  Future<List<MediaItem>> listUnselected({int? limit}) async {
    final rows = await _db.query(
      'evp_media_items',
      where: 'selected_at_ms IS NULL',
      orderBy: 'captured_at_ms ASC, created_at_ms ASC',
      limit: limit,
    );
    return [for (final r in rows) MediaItem.fromRow(r)];
  }

  /// Item counts per stage, for the hub's counters and the queue's chips.
  ///
  /// Scoped like every other read: a count that includes another event is worse
  /// than no count, because it looks authoritative.
  Future<Map<String, int>> stageCounts({String? eventId}) async {
    final scope = _eventScope(eventId);
    final rows = await _db.rawQuery(
      'SELECT stage, COUNT(*) AS n FROM evp_media_items '
      'WHERE 1 = 1${scope.clause} GROUP BY stage',
      scope.args,
    );
    return {
      for (final r in rows)
        (r['stage'] ?? '').toString(): (r['n'] as int?) ?? 0,
    };
  }

  // ------------------------------------------------------------------ updates

  /// Freezes [steps] onto the item and marks it selected.
  ///
  /// The chain is resolved once here rather than read live by each worker, so a
  /// settings change mid-event cannot alter work already in flight.
  Future<MediaItem?> markSelected(String id, List<String> steps) async {
    final item = await findById(id);
    if (item == null) return null;
    final now = _nowMs();
    final stage =
        steps.isEmpty ? MediaStage.done : MediaStage.forStep(steps.first);
    final updated = item.copyWith(
      steps: steps,
      stepIndex: 0,
      selectedAtMs: now,
      stage: steps.isEmpty ? stage : MediaStage.queued,
      updatedAtMs: now,
    );
    await _update(updated);
    return updated;
  }

  /// Advances past the completed step and re-derives the stage.
  Future<MediaItem?> advanceStep(String id) async {
    final item = await findById(id);
    if (item == null) return null;
    final next = item.stepIndex + 1;
    final now = _nowMs();
    final updated = item.copyWith(
      stepIndex: next,
      stage: next >= item.steps.length
          ? MediaStage.done
          : MediaStage.forStep(item.steps[next]),
      updatedAtMs: now,
    );
    await _update(updated);
    return updated;
  }

  /// Rewrites the frozen chain to drop `ai`, keeping whatever remains.
  ///
  /// The only sanctioned rewrite of a frozen list — an explicit operator action
  /// rather than settings drift leaking into in-flight work. Steps already
  /// completed stay completed: the new index is clamped so the item resumes at
  /// the right place rather than re-running framing or printing twice.
  Future<MediaItem?> skipAi(String id, {required List<String> newSteps}) async {
    final item = await findById(id);
    if (item == null) return null;
    final completed = item.steps.take(item.stepIndex).toSet();
    var index = 0;
    while (index < newSteps.length && completed.contains(newSteps[index])) {
      index++;
    }
    final now = _nowMs();
    final updated = item.copyWith(
      steps: newSteps,
      stepIndex: index,
      aiSkipped: true,
      stage: index >= newSteps.length
          ? MediaStage.done
          : MediaStage.forStep(newSteps[index]),
      updatedAtMs: now,
    );
    await _update(updated);
    return updated;
  }

  /// Removes an item and its renditions, returning it to "never seen".
  ///
  /// Used when the **source** went away mid-import rather than the photograph
  /// being at fault. Leaving a `FAILED` row behind would be worse than useless:
  /// the tier-1 dedupe matches on every row regardless of stage, so a rescan
  /// would report the photo as already imported and the operator could never
  /// reach it again. Deleting the row lets the rescan find it as new.
  ///
  /// A genuine decode failure still gets [MediaStage.failed] — that is a real
  /// fault and deserves to stay visible.
  Future<void> deleteItem(String id) async {
    await _db.delete(
      'evp_media_renditions',
      where: 'media_id = ?',
      whereArgs: [id],
    );
    await _db.delete('evp_media_items', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setStage(String id, String stage, {String? error}) async {
    await _db.update(
      'evp_media_items',
      <String, Object?>{
        'stage': stage,
        if (error != null) 'last_error': error,
        'updated_at_ms': _nowMs(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Records the server-side identifiers the AI step waits on.
  Future<void> setRemoteIds(
    String id, {
    String? sessionId,
    String? photoId,
  }) async {
    await _db.update(
      'evp_media_items',
      <String, Object?>{
        if (sessionId != null) 'remote_session_id': sessionId,
        if (photoId != null) 'remote_photo_id': photoId,
        'updated_at_ms': _nowMs(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> _update(MediaItem item) async {
    await _db.update(
      'evp_media_items',
      item.toRow(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  // --------------------------------------------------------------- renditions

  Future<void> putRendition(MediaRendition rendition) async {
    await _db.insert(
      'evp_media_renditions',
      rendition.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<MediaRendition>> renditionsFor(String mediaId) async {
    final rows = await _db.query(
      'evp_media_renditions',
      where: 'media_id = ?',
      whereArgs: [mediaId],
    );
    return [for (final r in rows) MediaRendition.fromRow(r)];
  }

  /// The rendition a print should use: framed, else AI, else the source copy.
  Future<MediaRendition?> bestRenditionForPrint(String mediaId) async {
    return MediaRendition.bestForPrint(await renditionsFor(mediaId));
  }

  Future<void> deleteRenditions(String mediaId) async {
    await _db.delete(
      'evp_media_renditions',
      where: 'media_id = ?',
      whereArgs: [mediaId],
    );
  }
}

/// A `WHERE` fragment and its arguments, for scoping a read to one event.
class _EventScope {
  const _EventScope(this.clause, this.args);

  final String clause;
  final List<Object?> args;
}
