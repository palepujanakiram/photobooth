import 'package:shared_preferences/shared_preferences.dart';

import '../../models/event_pipeline/media_item.dart';
import '../../models/event_pipeline/pipeline_job.dart';
import '../../utils/logger.dart';
import '../event_manager.dart';
import 'event_pipeline_align_api.dart';
import 'event_pipeline_ledger.dart';
import 'event_pipeline_queue.dart';
import 'event_pipeline_stats.dart';

/// Pushes local replica changes and pulls the shared ZenAI ledger.
///
/// Offline: the POST fails, the replica is unchanged, workers keep going.
/// Online: last-write-wins on `updatedAtMs` on both sides.
class EventPipelineAligner {
  EventPipelineAligner({
    EventPipelineAlignApi? api,
    EventPipelineLedger? ledger,
    EventPipelineQueue? queue,
    EventManager? events,
  })  : _api = api ?? EventPipelineAlignApi(),
        _ledger = ledger,
        _queue = queue,
        _events = events ?? EventManager();

  static const String _kCursor = 'evp_align_since_ms';

  final EventPipelineAlignApi _api;
  final EventPipelineLedger? _ledger;
  final EventPipelineQueue? _queue;
  final EventManager _events;

  Future<int> _readCursor() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kCursor) ?? 0;
  }

  Future<void> _writeCursor(int ms) async {
    if (ms <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kCursor, ms);
  }

  /// One round trip. Returns remote stats when the link answered.
  Future<EventPipelineStats?> align({String? eventId}) async {
    try {
      return await _align(eventId: eventId);
    } catch (e) {
      AppLogger.debug('Event pipeline align aborted: $e');
      return null;
    }
  }

  Future<EventPipelineStats?> _align({String? eventId}) async {
    final scope = (eventId ?? await _events.getEventId())?.trim() ?? '';
    final sinceMs = await _readCursor();
    var items = const <MediaItem>[];
    var jobs = const <PipelineJob>[];
    final ledger = _ledger;
    final queue = _queue;
    if (scope.isNotEmpty && ledger != null) {
      items = await ledger.listUpdatedSince(sinceMs, eventId: scope);
    }
    if (scope.isNotEmpty && queue != null) {
      jobs = await queue.listUpdatedSince(sinceMs, eventId: scope);
    }
    final snap = await _api.align(sinceMs: sinceMs, items: items, jobs: jobs);
    if (snap == null) return null;
    if (ledger != null) {
      for (final item in snap.items) {
        await ledger.upsertFromRemote(item);
      }
    }
    if (queue != null) {
      for (final job in snap.jobs) {
        await queue.upsertFromRemote(job);
      }
    }
    await _writeCursor(snap.serverNowMs);
    return snap.stats;
  }

  /// Stats-only read for runtimes with no replica (web).
  Future<EventPipelineStats?> readStats() async {
    return _api.readStats();
  }
}
