import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/event_pipeline/media_item.dart';
import '../../utils/json_parse_helpers.dart';
import '../event_manager.dart';
import 'event_pipeline_align_api.dart';
import 'event_pipeline_db.dart';
import 'event_pipeline_ledger.dart';
import 'event_pipeline_queue.dart';

/// Counts across the event processor, for the status strip every station carries.
///
/// Local replica first. When this runtime has no SQLite (web), [fallbackRead]
/// is the shared ZenAI ledger. Offline boxes never wait on that path.
class EventPipelineStats {
  const EventPipelineStats({
    this.imported = 0,
    this.queued = 0,
    this.ai = 0,
    this.framing = 0,
    this.printing = 0,
    this.done = 0,
    this.failed = 0,
    this.printPaused = false,
    this.queuePaused = false,
  });

  /// Imported but not yet selected.
  final int imported;

  final int queued;
  final int ai;
  final int framing;
  final int printing;
  final int done;
  final int failed;

  /// True when the print queue is held — ribbon, paper, jam or cover.
  final bool printPaused;

  /// True when the **operator** has held every stage. Distinct from
  /// [printPaused]: one is the printer's problem, the other is a deliberate
  /// hold, and telling an operator the wrong one wastes their time.
  final bool queuePaused;

  int get inFlight => queued + ai + framing + printing;
  int get total => imported + inFlight + done + failed;
  bool get isEmpty => total == 0;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'imported': imported,
        'queued': queued,
        'ai': ai,
        'framing': framing,
        'printing': printing,
        'done': done,
        'failed': failed,
        'printPaused': printPaused,
        'queuePaused': queuePaused,
      };

  factory EventPipelineStats.fromJson(Map<String, dynamic> json) {
    int n(String camel, String snake) =>
        JsonParseHelpers.intOrNull(json[camel] ?? json[snake]) ?? 0;
    return EventPipelineStats(
      imported: n('imported', 'imported'),
      queued: n('queued', 'queued'),
      ai: n('ai', 'ai'),
      framing: n('framing', 'framing'),
      printing: n('printing', 'printing'),
      done: n('done', 'done'),
      failed: n('failed', 'failed'),
      printPaused: json['printPaused'] == true || json['print_paused'] == true,
      queuePaused: json['queuePaused'] == true || json['queue_paused'] == true,
    );
  }

  /// One line, e.g. `Imported 1,511 · Queued 412 · AI 38 · Done 1,045`.
  ///
  /// Zero-valued stages are omitted so the line stays readable — an event with
  /// AI off should not carry a permanent "AI 0".
  String get summary {
    final parts = <String>[
      if (imported > 0) 'Imported ${_n(imported)}',
      if (queued > 0) 'Queued ${_n(queued)}',
      if (ai > 0) 'AI ${_n(ai)}',
      if (framing > 0) 'Framing ${_n(framing)}',
      if (printing > 0) 'Printing ${_n(printing)}',
      if (done > 0) 'Done ${_n(done)}',
      if (failed > 0) 'Failed ${_n(failed)}',
    ];
    if (parts.isEmpty) return 'Nothing imported yet';
    return parts.join(' · ');
  }

  static String _n(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  static EventPipelineStats fromStageCounts(
    Map<String, int> stages, {
    bool printPaused = false,
    bool queuePaused = false,
  }) {
    return EventPipelineStats(
      imported: stages[MediaStage.ingested] ?? 0,
      queued: stages[MediaStage.queued] ?? 0,
      ai: stages[MediaStage.ai] ?? 0,
      framing: stages[MediaStage.framing] ?? 0,
      printing: stages[MediaStage.printing] ?? 0,
      done: stages[MediaStage.done] ?? 0,
      failed: stages[MediaStage.failed] ?? 0,
      printPaused: printPaused,
      queuePaused: queuePaused,
    );
  }
}

/// Reads [EventPipelineStats] from the ledger.
///
/// The handle is opened **once** and reused. This is polled on a timer by every
/// station, and reopening per tick would re-run the schema DDL every few seconds
/// and leak a connection each time.
class EventPipelineStatsReader {
  EventPipelineStatsReader({
    Future<EventPipelineDb?> Function()? openDb,
    EventManager? events,
    Future<EventPipelineStats> Function()? fallbackRead,
    EventPipelineAlignApi? alignApi,
  })  : _openDb = openDb ?? EventPipelineDb.openDefault,
        _events = events ?? EventManager(),
        _fallbackRead = fallbackRead,
        _alignApi = alignApi;

  final Future<EventPipelineDb?> Function() _openDb;
  final EventManager _events;
  final Future<EventPipelineStats> Function()? _fallbackRead;
  EventPipelineAlignApi? _alignApi;

  static EventPipelineDb? _shared;
  static Future<EventPipelineDb?>? _opening;

  @visibleForTesting
  static void resetSharedForTests() {
    _shared = null;
    _opening = null;
  }

  Future<EventPipelineDb?> _database() {
    final ready = _shared;
    if (ready != null) return Future<EventPipelineDb?>.value(ready);
    // Guard against two ticks racing into a second open.
    return _opening ??= _openDb().then((db) {
      _shared = db;
      _opening = null;
      return db;
    });
  }

  /// Counts for the currently bound event only.
  ///
  /// Pass [eventId] to override; omit it and the bound event is read. Scoping
  /// matters more than it sounds: the ledger outlives an event, so an unscoped
  /// total at a wedding silently includes last weekend's party (spec §9B).
  Future<EventPipelineStats> read({String? eventId}) async {
    final db = await _database();
    // No database means no local replica — web uses the shared ledger instead.
    if (db == null) {
      return _readFallback();
    }
    final scope = eventId ?? await _events.getEventId();
    final queue = EventPipelineQueue(db: db);
    final stages = await EventPipelineLedger(db: db).stageCounts(
      eventId: scope,
    );
    return EventPipelineStats.fromStageCounts(
      stages,
      printPaused: await queue.isKindPaused('print'),
      queuePaused: await queue.isPaused(),
    );
  }

  Future<EventPipelineStats> _readFallback() async {
    final custom = _fallbackRead;
    if (custom != null) return custom();
    final api = _alignApi ??= EventPipelineAlignApi();
    return await api.readStats() ?? const EventPipelineStats();
  }
}
