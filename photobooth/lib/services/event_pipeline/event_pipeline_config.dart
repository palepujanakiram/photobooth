import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/event_pipeline/event_pipeline_flags.dart';
import '../../models/event_pipeline/event_pipeline_settings.dart';

/// The device's copy of the event's pipeline configuration.
///
/// Resolution is **cached backend flags → default**, and nothing else. ZenAI is
/// the single source of truth for how an event runs (operator screens spec §9):
/// there are deliberately no local overrides, so a device can never silently
/// disagree with the backend and an operator can never "fix" an event into a
/// state nobody can reproduce.
///
/// The flags are cached here so a cold offline start still knows the event's
/// shape without a network call.
class EventPipelineConfig {
  static const String _kCachedFlags = 'evp_cached_flags_json';

  /// Sync snapshot for callers that cannot await — routing decisions on the
  /// splash path in particular. Null until [resolve] has run once.
  static bool? _cachedPipelineEnabled;

  static bool get isPipelineEnabledCached => _cachedPipelineEnabled == true;

  @visibleForTesting
  static void resetCacheForTests() => _cachedPipelineEnabled = null;

  // ------------------------------------------------------------ backend flags

  /// Persists backend flags so a cold offline start knows the event's shape.
  Future<void> cacheFlags(EventPipelineFlags flags) async {
    final prefs = await SharedPreferences.getInstance();
    if (flags.isEmpty) {
      await prefs.remove(_kCachedFlags);
      return;
    }
    await prefs.setString(_kCachedFlags, jsonEncode(flags.toJson()));
  }

  Future<EventPipelineFlags> readCachedFlags() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCachedFlags);
    if (raw == null || raw.trim().isEmpty) return EventPipelineFlags.empty;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return EventPipelineFlags.empty;
      return EventPipelineFlags.fromEventJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      // A corrupt cache must not brick the station; inherit defaults instead.
      return EventPipelineFlags.empty;
    }
  }

  Future<void> clearCachedFlags() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCachedFlags);
    _cachedPipelineEnabled = null;
  }

  // --------------------------------------------------------------- resolution

  /// Resolves cached backend flags over [defaults] into a usable configuration.
  ///
  /// Pass [flags] to resolve against a freshly fetched event; omit it to fall
  /// back to whatever was last cached, which is what an offline start does.
  Future<EventPipelineSettings> resolve({
    EventPipelineFlags? flags,
    EventPipelineDefaults defaults = const EventPipelineDefaults(),
  }) async {
    final backend = flags ?? await readCachedFlags();

    final offlineMode = backend.offlineMode ?? false;

    final settings = EventPipelineSettings(
      pipelineEnabled: backend.pipelineEnabled ?? false,
      offlineMode: offlineMode,
      aiEnabled: backend.aiEnabled ?? defaults.aiEnabledDefault,
      themeId: backend.themeId,
      frameEnabled: backend.frameEnabled ?? defaults.frameEnabledDefault,
      frameId: backend.frameId,
      autoPrint: backend.autoPrint ?? defaults.printerEnabled,
      defaultCopies: backend.defaultCopies ?? 1,
      printSize: backend.printSize ?? defaults.printSize,
      qualityFactor: EventPipelineSettings.defaultQualityFactor,
      // Mirroring is a network activity, so an offline event never attempts it
      // regardless of what the backend asked for.
      mirrorEnabled: offlineMode ? false : (backend.mirrorEnabled ?? true),
      scanFolders: EventPipelineSettings.defaultScanFolders,
    );

    _cachedPipelineEnabled = settings.pipelineEnabled;
    return settings;
  }
}
