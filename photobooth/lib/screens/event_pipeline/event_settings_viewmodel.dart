import 'package:flutter/foundation.dart';

import '../../models/event_pipeline/event_frame.dart';
import '../../models/event_pipeline/event_pipeline_chain.dart';
import '../../models/event_pipeline/event_pipeline_settings.dart';
import '../../services/event_manager.dart';
import '../../services/event_pipeline/event_frame_cache.dart';
import '../../services/event_pipeline/event_pipeline_config.dart';
import '../../services/event_pipeline/event_pipeline_db.dart';
import '../../services/event_pipeline/event_pipeline_sync.dart';
import '../../utils/logger.dart';

/// One setting as the screen reads it: name, value, and what it does.
class EventSettingRow {
  const EventSettingRow({
    required this.label,
    required this.value,
    required this.subtitle,
    this.detail,
    this.warning,
  });

  final String label;

  /// Right-hand value, e.g. `on` or `4x6`.
  final String value;

  /// **One line saying what this setting does.**
  ///
  /// Read by an operator under time pressure who did not configure the event. A
  /// bare toggle labelled "Apply frame" does not tell them that turning it off
  /// means the prints come out plain.
  final String subtitle;

  /// Secondary line, e.g. the chosen theme or frame.
  final String? detail;

  /// Something that needs attention, e.g. frame artwork not downloaded.
  final String? warning;
}

/// The device's record of how this event is configured. Read-only.
///
/// ZenAI is the only source (spec §9). One source of truth means a device can
/// never silently disagree with the backend, and an operator can never "fix" an
/// event into a state nobody can reproduce — so `Sync` is the only control.
class EventSettingsViewModel extends ChangeNotifier {
  EventSettingsViewModel({
    EventPipelineConfig? config,
    EventManager? events,
    EventPipelineSync? sync,
    Future<EventPipelineDb?> Function()? openDb,
  })  : _config = config ?? EventPipelineConfig(),
        _events = events ?? EventManager(),
        _openDb = openDb ?? EventPipelineDb.openDefault {
    _sync = sync ??
        EventPipelineSync(
          config: _config,
          events: _events,
          frameCache: _buildFrameCache,
        );
  }

  final EventPipelineConfig _config;
  final EventManager _events;
  final Future<EventPipelineDb?> Function() _openDb;
  late final EventPipelineSync _sync;

  EventPipelineSettings? _settings;
  EventSyncStatus _syncStatus = const EventSyncStatus.never();
  FrameCacheStatus? _frames;
  bool _busy = false;
  bool _downloadingFrames = false;

  EventPipelineSettings? get settings => _settings;
  EventSyncStatus get syncStatus => _syncStatus;
  FrameCacheStatus? get frames => _frames;
  bool get isBusy => _busy;
  bool get isDownloadingFrames => _downloadingFrames;

  /// `Synced from ZenAI · 9 Sep 09:12`, the same timestamp the hub shows.
  String get syncedLabel {
    final at = _syncStatus.syncedAt;
    if (at == null) return 'Never synced';
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return 'Synced from ZenAI · ${at.day} ${_months[at.month - 1]} $hh:$mm';
  }

  /// The resolved chain, e.g. `AI → Frame → Print s4x6 · 1 copy`.
  ///
  /// The bottom line of the screen, and the one an operator checks when a print
  /// comes out looking wrong.
  String get chainSummary {
    final s = _settings;
    if (s == null) return '—';
    return EventPipelineChain.describe(
      s.resolveSteps(),
      s.defaultCopies,
      s.printSize,
    );
  }

  List<EventSettingRow> get rows {
    final s = _settings;
    if (s == null) return const [];
    return <EventSettingRow>[
      EventSettingRow(
        label: 'AI generation',
        value: s.aiEnabled ? 'on' : 'off',
        subtitle: 'Restyles each photo before framing.',
        detail: s.aiEnabled ? 'Theme · ${s.themeId ?? 'not set'}' : null,
        warning: s.aiEnabled && !s.canRunAi
            ? 'No theme is set, so AI will be skipped.'
            : null,
      ),
      EventSettingRow(
        label: 'Apply frame',
        value: s.frameEnabled ? 'on' : 'off',
        subtitle: "Adds the event's border to the finished photo. "
            'Downloaded once, then works offline.',
        detail: s.frameEnabled ? 'Frame · ${s.frameId ?? 'not set'}' : null,
        warning: s.frameEnabled ? _frameWarning() : null,
      ),
      EventSettingRow(
        label: 'Auto print',
        value: s.autoPrint ? 'on' : 'off',
        subtitle: 'Prints each photo as soon as it is ready. '
            'Off means you release prints yourself.',
      ),
      EventSettingRow(
        label: 'Copies per photo',
        value: '${s.defaultCopies}',
        subtitle: 'How many prints of each finished photo.',
      ),
      EventSettingRow(
        label: 'Print size',
        value: s.printSize,
        subtitle: 'Must match the media loaded in the printer.',
      ),
    ];
  }

  /// True when framing is on but the artwork is not on the device.
  ///
  /// The row doubles as the fix for the hub's "frames not cached" warning, so
  /// this is what gates the download button.
  bool get needsFrameDownload {
    final s = _settings;
    if (s == null || !s.frameEnabled) return false;
    return _frames == null || !_frames!.selectedIsCached;
  }

  String? _frameWarning() {
    if (_frames == null) return 'Cache state unknown — sync to check.';
    if (!_frames!.selectedIsCached) {
      return 'Artwork is not on this device, so framing cannot run offline.';
    }
    return null;
  }

  Future<void> start() async {
    _syncStatus = await _sync.status();
    await refresh();
  }

  /// Re-reads what is cached. No network.
  Future<void> refresh() async {
    _settings = await _config.resolve(
      defaults: EventPipelineDefaults(
        photoMode: await _events.getPhotoModeOverride() ?? 'BOTH',
        frameCount: await _events.getFrameCount(),
      ),
    );
    _frames = await _readFrameStatus();
    notifyListeners();
  }

  /// Re-fetches on demand, for when something changed on the backend mid-event.
  /// The only control on this screen.
  Future<void> sync() async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      _syncStatus = await _sync.sync();
    } catch (e, st) {
      AppLogger.error('Settings sync failed', error: e, stackTrace: st);
    } finally {
      _busy = false;
      await refresh();
    }
  }

  /// Downloads the event's frame artwork on demand.
  ///
  /// Separate from [sync] because the two fail differently: settings can arrive
  /// while an overlay does not, and an operator staring at "frames not cached"
  /// needs to retry the download, not the whole event.
  Future<void> downloadFrames() async {
    if (_downloadingFrames) return;
    _downloadingFrames = true;
    notifyListeners();
    try {
      final eventId = await _events.getEventId();
      final cache = await _buildFrameCache();
      if (eventId == null || cache == null) return;
      _frames = await cache.refresh(
        eventId: eventId,
        selectedFrameId: _settings?.frameId,
      );
    } catch (e, st) {
      AppLogger.error('Frame download failed', error: e, stackTrace: st);
    } finally {
      _downloadingFrames = false;
      notifyListeners();
    }
  }

  Future<FrameCacheStatus?> _readFrameStatus() async {
    try {
      final eventId = await _events.getEventId();
      if (eventId == null) return null;
      final cache = await _buildFrameCache();
      if (cache == null) return null;
      return await cache.status(
        eventId: eventId,
        selectedFrameId: _settings?.frameId,
      );
    } catch (e) {
      AppLogger.debug('Frame status unreadable: $e');
      return null;
    }
  }

  Future<EventFrameCache?> _buildFrameCache() async {
    final db = await _openDb();
    return db == null ? null : EventFrameCache(db: db);
  }

  static const List<String> _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}
