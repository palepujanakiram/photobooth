import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/event_pipeline/event_pipeline_flags.dart';
import '../../models/event_pipeline/event_pipeline_settings.dart';

/// Local overrides for the event pipeline, layered over backend event flags.
///
/// Resolution order is **local override → backend flag → default**, and a null
/// override means "inherit", mirroring `KioskManager`'s existing idiom. The
/// override exists so a box that has never reached the backend for this event
/// can still be configured on site.
///
/// The backend flags themselves are cached here too, so a cold offline start
/// still knows the event's shape without a network call.
class EventPipelineConfig {
  static const String _kPipelineEnabled = 'evp_pipeline_enabled';
  static const String _kOfflineMode = 'evp_offline_mode';
  static const String _kAiEnabled = 'evp_ai_enabled';
  static const String _kThemeId = 'evp_theme_id';
  static const String _kFrameEnabled = 'evp_frame_enabled';
  static const String _kFrameId = 'evp_frame_id';
  static const String _kAutoPrint = 'evp_auto_print';
  static const String _kDefaultCopies = 'evp_default_copies';
  static const String _kPrintSize = 'evp_print_size';
  static const String _kQualityFactor = 'evp_quality_factor';
  static const String _kMirrorEnabled = 'evp_mirror_enabled';
  static const String _kScanFolders = 'evp_scan_folders';
  static const String _kCachedFlags = 'evp_cached_flags_json';

  /// Sync snapshot for callers that cannot await — routing decisions on the
  /// splash path in particular. Null until [resolve] has run once.
  static bool? _cachedPipelineEnabled;

  static bool get isPipelineEnabledCached => _cachedPipelineEnabled == true;

  @visibleForTesting
  static void resetCacheForTests() => _cachedPipelineEnabled = null;

  // ---------------------------------------------------------------- overrides

  Future<bool?> getPipelineEnabledOverride() => _readBool(_kPipelineEnabled);
  Future<void> setPipelineEnabledOverride(bool? v) =>
      _writeBool(_kPipelineEnabled, v);

  Future<bool?> getOfflineModeOverride() => _readBool(_kOfflineMode);
  Future<void> setOfflineModeOverride(bool? v) => _writeBool(_kOfflineMode, v);

  Future<bool?> getAiEnabledOverride() => _readBool(_kAiEnabled);
  Future<void> setAiEnabledOverride(bool? v) => _writeBool(_kAiEnabled, v);

  Future<String?> getThemeIdOverride() => _readString(_kThemeId);
  Future<void> setThemeIdOverride(String? v) => _writeString(_kThemeId, v);

  Future<bool?> getFrameEnabledOverride() => _readBool(_kFrameEnabled);
  Future<void> setFrameEnabledOverride(bool? v) => _writeBool(_kFrameEnabled, v);

  Future<String?> getFrameIdOverride() => _readString(_kFrameId);
  Future<void> setFrameIdOverride(String? v) => _writeString(_kFrameId, v);

  Future<bool?> getAutoPrintOverride() => _readBool(_kAutoPrint);
  Future<void> setAutoPrintOverride(bool? v) => _writeBool(_kAutoPrint, v);

  Future<String?> getPrintSizeOverride() => _readString(_kPrintSize);
  Future<void> setPrintSizeOverride(String? v) => _writeString(_kPrintSize, v);

  Future<bool?> getMirrorEnabledOverride() => _readBool(_kMirrorEnabled);
  Future<void> setMirrorEnabledOverride(bool? v) =>
      _writeBool(_kMirrorEnabled, v);

  Future<int?> getDefaultCopiesOverride() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_kDefaultCopies)) return null;
    final v = prefs.getInt(_kDefaultCopies);
    return (v == null || v < 1) ? null : v;
  }

  Future<void> setDefaultCopiesOverride(int? v) async {
    final prefs = await SharedPreferences.getInstance();
    if (v == null || v < 1) {
      await prefs.remove(_kDefaultCopies);
      return;
    }
    await prefs.setInt(_kDefaultCopies, v);
  }

  Future<double?> getQualityFactorOverride() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_kQualityFactor)) return null;
    return _clampQuality(prefs.getDouble(_kQualityFactor));
  }

  Future<void> setQualityFactorOverride(double? v) async {
    final prefs = await SharedPreferences.getInstance();
    final clamped = _clampQuality(v);
    if (clamped == null) {
      await prefs.remove(_kQualityFactor);
      return;
    }
    await prefs.setDouble(_kQualityFactor, clamped);
  }

  Future<List<String>?> getScanFoldersOverride() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kScanFolders);
    if (raw == null) return null;
    final cleaned = _normalizeFolders(raw);
    return cleaned.isEmpty ? null : cleaned;
  }

  Future<void> setScanFoldersOverride(List<String>? folders) async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned = folders == null ? const <String>[] : _normalizeFolders(folders);
    if (cleaned.isEmpty) {
      await prefs.remove(_kScanFolders);
      return;
    }
    await prefs.setStringList(_kScanFolders, cleaned);
  }

  /// Drops every override back to "inherit".
  Future<void> clearOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in const <String>[
      _kPipelineEnabled,
      _kOfflineMode,
      _kAiEnabled,
      _kThemeId,
      _kFrameEnabled,
      _kFrameId,
      _kAutoPrint,
      _kDefaultCopies,
      _kPrintSize,
      _kQualityFactor,
      _kMirrorEnabled,
      _kScanFolders,
    ]) {
      await prefs.remove(key);
    }
    _cachedPipelineEnabled = null;
  }

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
  }

  // ---------------------------------------------------------------- resolution

  /// Resolves override → backend flag → default into a usable configuration.
  ///
  /// Pass [flags] to resolve against a freshly fetched event; omit it to fall
  /// back to whatever was last cached, which is what an offline start does.
  Future<EventPipelineSettings> resolve({
    EventPipelineFlags? flags,
    EventPipelineDefaults defaults = const EventPipelineDefaults(),
  }) async {
    final backend = flags ?? await readCachedFlags();

    final pipelineEnabled = await getPipelineEnabledOverride() ??
        backend.pipelineEnabled ??
        false;
    final offlineMode =
        await getOfflineModeOverride() ?? backend.offlineMode ?? false;
    final frameEnabled = await getFrameEnabledOverride() ??
        backend.frameEnabled ??
        defaults.frameEnabledDefault;

    final settings = EventPipelineSettings(
      pipelineEnabled: pipelineEnabled,
      offlineMode: offlineMode,
      aiEnabled: await getAiEnabledOverride() ??
          backend.aiEnabled ??
          defaults.aiEnabledDefault,
      themeId: await getThemeIdOverride() ?? backend.themeId,
      frameEnabled: frameEnabled,
      frameId: await getFrameIdOverride() ?? backend.frameId,
      autoPrint: await getAutoPrintOverride() ??
          backend.autoPrint ??
          defaults.printerEnabled,
      defaultCopies:
          await getDefaultCopiesOverride() ?? backend.defaultCopies ?? 1,
      printSize: await getPrintSizeOverride() ??
          backend.printSize ??
          defaults.printSize,
      qualityFactor: await getQualityFactorOverride() ??
          EventPipelineSettings.defaultQualityFactor,
      // Mirroring is a network activity, so an offline event never attempts it
      // regardless of what the backend or an override asked for.
      mirrorEnabled: offlineMode
          ? false
          : (await getMirrorEnabledOverride() ?? backend.mirrorEnabled ?? true),
      scanFolders: await getScanFoldersOverride() ??
          EventPipelineSettings.defaultScanFolders,
    );

    _cachedPipelineEnabled = settings.pipelineEnabled;
    return settings;
  }

  // -------------------------------------------------------------------- utils

  Future<bool?> _readBool(String key) async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(key)) return null;
    return prefs.getBool(key);
  }

  Future<void> _writeBool(String key, bool? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(key);
      return;
    }
    await prefs.setBool(key, value);
  }

  Future<String?> _readString(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(key)?.trim() ?? '';
    return v.isEmpty ? null : v;
  }

  Future<void> _writeString(String key, String? value) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, trimmed);
  }

  /// Below 0.5 the derivative loses print detail; above 2.0 it wastes disk for
  /// resolution the DS-RX1 cannot render.
  static double? _clampQuality(double? v) {
    if (v == null || v.isNaN) return null;
    if (v < 0.5) return 0.5;
    if (v > 2.0) return 2.0;
    return v;
  }

  /// Trims separators so `'/DCIM/'`, `'DCIM'` and `'dcim'` all match the same
  /// MediaStore `relative_path` prefix.
  static List<String> _normalizeFolders(Iterable<String> folders) {
    final out = <String>[];
    for (final raw in folders) {
      final trimmed = raw.trim().replaceAll(RegExp(r'^/+|/+$'), '');
      if (trimmed.isEmpty) continue;
      if (!out.contains(trimmed)) out.add(trimmed);
    }
    return out;
  }
}
