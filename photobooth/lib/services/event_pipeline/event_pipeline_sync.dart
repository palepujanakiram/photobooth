import '../../models/event_pipeline/event_frame.dart';
import '../../models/event_pipeline/event_pipeline_flags.dart';
import '../../utils/logger.dart';
import '../event_manager.dart';
import 'event_frame_cache.dart';
import 'event_pipeline_config.dart';
import 'event_pipeline_dev_config.dart';
import 'event_pipeline_event_fetch.dart';

/// How the device came by the settings it is running on.
enum EventSyncState {
  /// Fetched from ZenAI just now.
  synced,

  /// The fetch failed, but this device has synced this event before and is
  /// running on that cache. The event runs; the hub says which day it is from.
  usingCache,

  /// Never synced this event. Import and Capture stay blocked — a photo taken
  /// in now would have no chain frozen onto it and would sit at INGESTED
  /// forever (screens spec §3A).
  never,
}

/// What the hub and the settings screen render for the sync row.
class EventSyncStatus {
  const EventSyncStatus({
    required this.state,
    this.eventCode,
    this.syncedAtMs,
    this.frames,
    this.error,
  });

  const EventSyncStatus.never({this.error})
      : state = EventSyncState.never,
        eventCode = null,
        syncedAtMs = null,
        frames = null;

  final EventSyncState state;
  final String? eventCode;

  /// When this event's settings last came from ZenAI.
  final int? syncedAtMs;

  /// Frame cache state after the sync, when there was a database to record it
  /// in. Null means framing readiness is simply not known yet.
  final FrameCacheStatus? frames;

  /// The reason a fetch failed, for the tappable explanation on the hub.
  final String? error;

  /// The gate on Import and Capture. Blocking is the honest behaviour: the card
  /// is not going anywhere, and a sync is seconds once there is signal.
  bool get hasSyncedOnce => state != EventSyncState.never;

  bool get isFresh => state == EventSyncState.synced;

  DateTime? get syncedAt => syncedAtMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(syncedAtMs!);

  EventSyncStatus copyWith({FrameCacheStatus? frames}) {
    return EventSyncStatus(
      state: state,
      eventCode: eventCode,
      syncedAtMs: syncedAtMs,
      frames: frames ?? this.frames,
      error: error,
    );
  }
}

/// Fetches the bound event's pipeline config, caches it, and warms the frames.
///
/// ZenAI is the only source of event settings (screens spec §9), so this is the
/// single write path into [EventPipelineConfig]'s cache. It is called once when
/// an event is bound and again whenever an operator taps the timestamp on the
/// hub, and it never throws — a failed sync is a state the hub renders, not an
/// error the caller handles.
class EventPipelineSync {
  EventPipelineSync({
    EventPipelineConfig? config,
    EventManager? events,
    Future<Map<String, dynamic>?> Function(String code)? fetchEvent,
    Future<EventFrameCache?> Function()? frameCache,
    int Function()? nowMs,
  })  : _config = config ?? EventPipelineConfig(),
        _events = events ?? EventManager(),
        _fetchEvent = fetchEvent ?? EventPipelineEventFetch().call,
        _frameCache = frameCache ?? (() async => null),
        _nowMs = nowMs ?? _defaultNowMs;

  final EventPipelineConfig _config;
  final EventManager _events;
  final Future<Map<String, dynamic>?> Function(String code) _fetchEvent;
  final Future<EventFrameCache?> Function() _frameCache;
  final int Function() _nowMs;

  static int _defaultNowMs() => DateTime.now().millisecondsSinceEpoch;

  /// What is known without touching the network.
  ///
  /// The hub renders this immediately on entry and replaces it when [sync]
  /// lands, so a slow venue link never leaves the operator on a spinner.
  Future<EventSyncStatus> status() async {
    final code = await _events.getEventCode();
    if (code == null) {
      return const EventSyncStatus.never(error: 'No event is bound.');
    }
    final syncedAtMs = await _config.readSyncedAtMs(code);
    if (syncedAtMs == null) {
      return EventSyncStatus(state: EventSyncState.never, eventCode: code);
    }
    return EventSyncStatus(
      state: EventSyncState.usingCache,
      eventCode: code,
      syncedAtMs: syncedAtMs,
    );
  }

  /// Fetches the event, caches its flags, then warms the frame overlays.
  Future<EventSyncStatus> sync() async {
    final code = await _events.getEventCode();
    if (code == null) {
      return const EventSyncStatus.never(error: 'No event is bound.');
    }

    final body = await _fetchEvent(code);
    if (body == null) {
      return _withFrames(await _fallback(code));
    }

    final flags = _flagsFrom(body);
    await _config.cacheFlags(flags);
    final now = _nowMs();
    await _config.recordSyncedAt(code, now);

    return _withFrames(EventSyncStatus(
      state: EventSyncState.synced,
      eventCode: code,
      syncedAtMs: now,
    ));
  }

  /// A failed fetch falls back to the cache when there is one, and says so
  /// plainly when there is not.
  Future<EventSyncStatus> _fallback(String code) async {
    final syncedAtMs = await _config.readSyncedAtMs(code);
    if (syncedAtMs == null) {
      return EventSyncStatus(
        state: EventSyncState.never,
        eventCode: code,
        error: 'Could not reach ZenAI, and this device has no settings for '
            '$code yet.',
      );
    }
    return EventSyncStatus(
      state: EventSyncState.usingCache,
      eventCode: code,
      syncedAtMs: syncedAtMs,
      error: 'Could not reach ZenAI — running on the last synced settings.',
    );
  }

  /// Reads the pipeline flags out of the raw body, filling the two ids the
  /// backend does not carry yet from the catalogue it does.
  EventPipelineFlags _flagsFrom(Map<String, dynamic> body) {
    final parsed = EventPipelineFlags.fromEventJson(body);
    final nested = body['event'];
    final src = nested is Map ? Map<String, dynamic>.from(nested) : body;

    return parsed.copyWith(
      themeId: EventPipelineDevConfig.resolveThemeId(
        fromBackend: parsed.themeId,
        catalogue: _idList(src['themeIds'] ?? src['theme_ids']),
      ),
      frameId: EventPipelineDevConfig.resolveFrameId(
        fromBackend: parsed.frameId,
        catalogue: _idList(src['frameIds'] ?? src['frame_ids']),
      ),
    );
  }

  /// Downloads any overlay not already on disk, so framing works once the link
  /// is gone. Best effort: a frame that will not download is a readiness
  /// warning on the hub, not a failed sync.
  Future<EventSyncStatus> _withFrames(EventSyncStatus status) async {
    if (!status.hasSyncedOnce) return status;
    final eventId = await _events.getEventId();
    if (eventId == null) return status;

    try {
      final cache = await _frameCache();
      if (cache == null) return status;
      final settings = await _config.resolve();
      final frames = await cache.refresh(
        eventId: eventId,
        selectedFrameId: settings.frameId,
      );
      return status.copyWith(frames: frames);
    } catch (e, st) {
      AppLogger.error('Frame refresh failed', error: e, stackTrace: st);
      return status;
    }
  }

  static List<String> _idList(Object? raw) {
    if (raw is! List) return const <String>[];
    return [
      for (final value in raw)
        if (value.toString().trim().isNotEmpty) value.toString().trim(),
    ];
  }
}
