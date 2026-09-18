import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/event_pipeline/event_pipeline_flags.dart';
import '../../models/event_pipeline/event_pipeline_settings.dart';

/// The device's copy of the event's pipeline configuration.
///
/// Resolution is **local auto-print override → cached backend flags → default**.
/// ZenAI is otherwise the single source of truth for how an event runs (operator
/// screens spec §9): every other setting has no local override, so a device
/// cannot silently disagree with the backend and an operator cannot "fix" an
/// event into a state nobody can reproduce.
///
/// The flags are cached here so a cold offline start still knows the event's
/// shape without a network call.
class EventPipelineConfig {
  static const String _kCachedFlags = 'evp_cached_flags_json';
  static const String _kSyncedAtMs = 'evp_flags_synced_at_ms';
  static const String _kSyncedCode = 'evp_flags_synced_code';
  static const String _kAutoPrintOverride = 'evp_auto_print_override';

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
    await prefs.remove(_kSyncedAtMs);
    await prefs.remove(_kSyncedCode);
    await prefs.remove(_kAutoPrintOverride);
    _cachedPipelineEnabled = null;
  }

  // ------------------------------------------------------- auto-print override

  /// **Stopgap. Remove once ZenAI's admin UI can set `autoPrint` per event.**
  ///
  /// TODO(event-pipeline): delete this override and its UI when
  /// `client/src/pages/admin/event-detail.tsx` grows an event-settings section
  /// wired to the `PATCH /api/events/:id/settings` endpoint that already
  /// exists. The settings row should go back to read-only then, per spec §9.
  ///
  /// The column (`events.auto_print`) defaults to `false` and **nothing in the
  /// admin UI ever writes it**, so `/settings` returns an explicit `false` for
  /// every event — not a null that could fall through to
  /// [EventPipelineDefaults.printerEnabled]. The print step is therefore never
  /// in a resolved chain and every print has to be released by hand. Until the
  /// backend has a control, this is the only way to turn auto print on.
  ///
  /// Null means "no local opinion", which is what makes this removable: the day
  /// the admin UI lands, a device that was never toggled already defers to it.
  Future<bool?> readAutoPrintOverride() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAutoPrintOverride);
  }

  /// Records the operator's choice, or clears it with null to defer to ZenAI.
  Future<void> setAutoPrintOverride(bool? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_kAutoPrintOverride);
      return;
    }
    await prefs.setBool(_kAutoPrintOverride, value);
  }

  // ------------------------------------------------------------- sync record

  /// Records that [eventCode] reached the backend at [atMs].
  ///
  /// Separate from [cacheFlags] on purpose: a backend that returns no pipeline
  /// fields at all still **synced**, and the event then runs on defaults. Tying
  /// the timestamp to the flags would leave that event permanently blocked from
  /// importing (screens spec §3A).
  Future<void> recordSyncedAt(String eventCode, int atMs) async {
    final code = eventCode.trim().toUpperCase();
    if (code.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    // An auto-print choice belongs to the event it was made for. A device moves
    // between events, and inheriting last weekend's "auto print on" would start
    // printing an event nobody asked it to print.
    final previous = prefs.getString(_kSyncedCode)?.trim().toUpperCase();
    if (previous != null && previous != code) {
      await prefs.remove(_kAutoPrintOverride);
    }
    await prefs.setInt(_kSyncedAtMs, atMs);
    await prefs.setString(_kSyncedCode, code);
  }

  /// When [eventCode] last synced, or null if this device never has.
  ///
  /// Scoped to the code because a device moves between events: inheriting last
  /// weekend's "synced 09:12" would unblock import for an event whose settings
  /// this device has never actually seen.
  Future<int?> readSyncedAtMs(String eventCode) async {
    final code = eventCode.trim().toUpperCase();
    if (code.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final storedCode = prefs.getString(_kSyncedCode)?.trim().toUpperCase();
    if (storedCode == null || storedCode != code) return null;
    return prefs.getInt(_kSyncedAtMs);
  }

  /// Gate for import and capture — no photo enters without a chain to run.
  Future<bool> hasSyncedOnce(String eventCode) async =>
      await readSyncedAtMs(eventCode) != null;

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
    final autoPrintOverride = await readAutoPrintOverride();

    final offlineMode = backend.offlineMode ?? false;

    final settings = EventPipelineSettings(
      pipelineEnabled: backend.pipelineEnabled ?? false,
      offlineMode: offlineMode,
      aiEnabled: backend.aiEnabled ?? defaults.aiEnabledDefault,
      themeId: backend.themeId,
      frameEnabled: backend.frameEnabled ?? defaults.frameEnabledDefault,
      frameId: backend.frameId,
      // The operator's local choice wins while ZenAI has no control for this.
      autoPrint:
          autoPrintOverride ?? backend.autoPrint ?? defaults.printerEnabled,
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
