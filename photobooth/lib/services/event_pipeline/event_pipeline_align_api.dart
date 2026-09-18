import 'package:dio/dio.dart';

import '../../models/event_pipeline/media_item.dart';
import '../../models/event_pipeline/pipeline_job.dart';
import '../../utils/json_parse_helpers.dart';
import '../../utils/logger.dart';
import '../api_service_dio.dart';
import '../event_manager.dart';
import '../kiosk_manager.dart';
import 'event_pipeline_stats.dart';

/// Result of one align round-trip with ZenAI.
class EventPipelineAlignSnapshot {
  const EventPipelineAlignSnapshot({
    required this.serverNowMs,
    required this.items,
    required this.jobs,
    required this.stats,
  });

  final int serverNowMs;
  final List<MediaItem> items;
  final List<PipelineJob> jobs;
  final EventPipelineStats stats;
}

/// HTTP client for the shared event-booth ledger.
///
/// Same kiosk+event codes as the old station APIs. Failures return null so an
/// offline box keeps working from its replica.
class EventPipelineAlignApi {
  EventPipelineAlignApi({
    Dio? dio,
    EventManager? events,
    KioskManager? kiosks,
  })  : _dio = dio ?? createProductionApiDio(),
        _events = events ?? EventManager(),
        _kiosks = kiosks ?? KioskManager();

  final Dio _dio;
  final EventManager _events;
  final KioskManager _kiosks;

  Future<Map<String, String>?> _codes() async {
    final kiosk = ((await _kiosks.getKioskCode()) ?? '').trim();
    final event = ((await _events.getEventCode()) ?? '').trim();
    if (kiosk.isEmpty || event.isEmpty) return null;
    return {'kioskCode': kiosk, 'eventCode': event};
  }

  Future<EventPipelineStats?> readStats() async {
    final codes = await _codes();
    if (codes == null) return null;
    try {
      final r = await _dio.get<dynamic>(
        '/api/event/pipeline/stats',
        queryParameters: codes,
        options: Options(
          responseType: ResponseType.json,
          validateStatus: (c) => c != null && c >= 200 && c < 500,
        ),
      );
      if (r.statusCode != null && r.statusCode! >= 400) return null;
      final data = r.data;
      if (data is! Map) return null;
      final stats = data['stats'];
      if (stats is! Map) return null;
      return EventPipelineStats.fromJson(Map<String, dynamic>.from(stats));
    } catch (e) {
      AppLogger.debug('Event pipeline stats fetch failed: $e');
      return null;
    }
  }

  /// Read-only snapshot for operator consoles with no local replica.
  Future<EventPipelineAlignSnapshot?> readSnapshot({int sinceMs = 0}) async {
    final codes = await _codes();
    if (codes == null) return null;
    try {
      final r = await _dio.get<dynamic>(
        '/api/event/pipeline/snapshot',
        queryParameters: <String, dynamic>{...codes, 'sinceMs': sinceMs},
        options: Options(
          responseType: ResponseType.json,
          validateStatus: (c) => c != null && c >= 200 && c < 500,
        ),
      );
      if (r.statusCode != null && r.statusCode! >= 400) return null;
      final data = r.data;
      if (data is! Map) return null;
      return _snapshotFrom(Map<String, dynamic>.from(data));
    } catch (e) {
      AppLogger.debug('Event pipeline snapshot fetch failed: $e');
      return null;
    }
  }

  Future<EventPipelineAlignSnapshot?> align({
    int sinceMs = 0,
    List<MediaItem> items = const <MediaItem>[],
    List<PipelineJob> jobs = const <PipelineJob>[],
  }) async {
    final codes = await _codes();
    if (codes == null) return null;
    try {
      final r = await _dio.post<dynamic>(
        '/api/event/pipeline/align',
        data: <String, dynamic>{
          ...codes,
          'sinceMs': sinceMs,
          'items': [for (final item in items) item.toJson()],
          'jobs': [for (final job in jobs) job.toJson()],
        },
        options: Options(
          responseType: ResponseType.json,
          validateStatus: (c) => c != null && c >= 200 && c < 500,
        ),
      );
      if (r.statusCode != null && r.statusCode! >= 400) return null;
      final data = r.data;
      if (data is! Map) return null;
      return _snapshotFrom(Map<String, dynamic>.from(data));
    } catch (e) {
      AppLogger.debug('Event pipeline align failed: $e');
      return null;
    }
  }

  static EventPipelineAlignSnapshot _snapshotFrom(Map<String, dynamic> data) {
    final itemsRaw = data['items'];
    final jobsRaw = data['jobs'];
    final statsRaw = data['stats'];
    return EventPipelineAlignSnapshot(
      serverNowMs: JsonParseHelpers.intOrNull(data['serverNowMs']) ?? 0,
      items: itemsRaw is List
          ? [
              for (final row in itemsRaw)
                if (row is Map)
                  MediaItem.fromJson(Map<String, dynamic>.from(row)),
            ]
          : const <MediaItem>[],
      jobs: jobsRaw is List
          ? [
              for (final row in jobsRaw)
                if (row is Map)
                  PipelineJob.fromJson(Map<String, dynamic>.from(row)),
            ]
          : const <PipelineJob>[],
      stats: statsRaw is Map
          ? EventPipelineStats.fromJson(Map<String, dynamic>.from(statsRaw))
          : const EventPipelineStats(),
    );
  }
}