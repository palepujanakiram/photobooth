import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/event_info_model.dart';
import '../utils/event_station_role.dart';
import 'catalog_disk_cache.dart';

/// Cached booth event from `/api/event/verify` (additive to [KioskManager]).
class EventManager {
  EventManager({CatalogDiskCache? diskCache})
      : _diskCache = diskCache ?? CatalogDiskCache();

  final CatalogDiskCache _diskCache;
  static const String _kPrefsEventCode = 'event_code';
  static const String _kPrefsEventId = 'event_id';
  static const String _kPrefsEventPhotoMode = 'event_photo_mode';
  static const String _kPrefsEventThemeCount = 'event_theme_count';
  static const String _kPrefsEventFrameCount = 'event_frame_count';
  static const String _kPrefsEventName = 'event_name';
  static const String _kPrefsEventJson = 'event_bound_json';
  static const String _kPrefsStationRole = 'event_station_role';
  static const String _kPrefsDeviceId = 'event_station_device_id';

  static String? _cachedCode;
  static String? _cachedPhotoMode;
  static String? _cachedStationRole;

  String _diskKey(String code) => 'event_${code.trim().toUpperCase()}';

  @visibleForTesting
  static void resetCacheForTests() {
    _cachedCode = null;
    _cachedPhotoMode = null;
    _cachedStationRole = null;
  }

  Future<String?> getEventCode() async {
    if (_cachedCode != null) {
      return _cachedCode!.isEmpty ? null : _cachedCode;
    }
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_kPrefsEventCode);
    final trimmed = v?.trim() ?? '';
    _cachedCode = trimmed;
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<String?> getEventId() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_kPrefsEventId)?.trim() ?? '';
    return v.isEmpty ? null : v;
  }

  Future<String?> getPhotoModeOverride() async {
    if (_cachedPhotoMode != null) {
      return _cachedPhotoMode!.isEmpty ? null : _cachedPhotoMode;
    }
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_kPrefsEventPhotoMode)?.trim() ?? '';
    _cachedPhotoMode = v;
    return v.isEmpty ? null : v;
  }

  Future<int> getThemeCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kPrefsEventThemeCount) ?? 0;
  }

  Future<int> getFrameCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kPrefsEventFrameCount) ?? 0;
  }

  Future<String?> getEventName() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_kPrefsEventName)?.trim() ?? '';
    return v.isEmpty ? null : v;
  }

  Future<bool> isEventBound() async {
    final code = await getEventCode();
    return code != null && code.isNotEmpty;
  }

  Future<String?> getStationRole() async {
    if (_cachedStationRole != null) {
      return _cachedStationRole!.isEmpty ? null : _cachedStationRole;
    }
    final prefs = await SharedPreferences.getInstance();
    final parsed =
        EventStationRole.tryParse(prefs.getString(_kPrefsStationRole));
    _cachedStationRole = parsed ?? '';
    return parsed;
  }

  Future<void> setStationRole(String? role) async {
    final parsed = EventStationRole.tryParse(role);
    _cachedStationRole = parsed ?? '';
    final prefs = await SharedPreferences.getInstance();
    if (parsed == null) {
      await prefs.remove(_kPrefsStationRole);
      return;
    }
    await prefs.setString(_kPrefsStationRole, parsed);
  }

  Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_kPrefsDeviceId)?.trim() ?? '';
    if (existing.isNotEmpty) return existing;
    final id = const Uuid().v4();
    await prefs.setString(_kPrefsDeviceId, id);
    return id;
  }

  Future<void> setEventCode(String? code) async {
    final trimmed = (code ?? '').trim().toUpperCase();
    _cachedCode = trimmed;
    final prefs = await SharedPreferences.getInstance();
    if (trimmed.isEmpty) {
      await prefs.remove(_kPrefsEventCode);
      return;
    }
    await prefs.setString(_kPrefsEventCode, trimmed);
  }

  Future<void> setPhotoModeOverride(String? mode) async {
    final trimmed = (mode ?? '').trim();
    _cachedPhotoMode = trimmed;
    final prefs = await SharedPreferences.getInstance();
    if (trimmed.isEmpty) {
      await prefs.remove(_kPrefsEventPhotoMode);
      return;
    }
    await prefs.setString(_kPrefsEventPhotoMode, trimmed);
  }

  Future<void> cacheVerifyResult(EventInfoModel event) async {
    await setEventCode(event.code);
    await setPhotoModeOverride(event.photoMode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsEventId, event.id);
    final name = event.name?.trim() ?? '';
    if (name.isNotEmpty) {
      await prefs.setString(_kPrefsEventName, name);
    } else {
      await prefs.remove(_kPrefsEventName);
    }
    await prefs.setInt(_kPrefsEventThemeCount, event.themeCount);
    await prefs.setInt(_kPrefsEventFrameCount, event.frameCount);
    final payload = event.toJson();
    await prefs.setString(_kPrefsEventJson, jsonEncode(payload));
    await _diskCache.writeJson(_diskKey(event.code), payload);
  }

  /// Returns the last verified row for this exact event code.
  Future<EventInfoModel?> readCachedEvent(String code) async {
    final fromDisk = EventInfoModel.fromCache(
      await _diskCache.readJson(_diskKey(code)),
      expectedCode: code,
    );
    if (fromDisk != null) return fromDisk;
    return _readPrefsCachedEvent(code);
  }

  Future<EventInfoModel?> _readPrefsCachedEvent(String code) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefsEventJson);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return EventInfoModel.fromCache(jsonDecode(raw), expectedCode: code);
    } catch (_) {
      return null;
    }
  }

  Future<EventInfoModel?> readBoundEvent() async {
    final code = await getEventCode();
    if (code == null) return null;
    return readCachedEvent(code);
  }

  /// Cache first, then an optional live fetch so web (no disk cache) can
  /// still paint event chrome after a code-only bind.
  Future<EventInfoModel?> hydrateBoundEvent({
    Future<EventInfoModel?> Function(String code)? fetchLive,
  }) async {
    final cached = await readBoundEvent();
    if (cached != null) return cached;
    if (fetchLive == null) return null;
    final code = await getEventCode();
    if (code == null) return null;
    return _fetchAndCacheBoundEvent(code, fetchLive);
  }

  Future<EventInfoModel?> _fetchAndCacheBoundEvent(
    String code,
    Future<EventInfoModel?> Function(String code) fetchLive,
  ) async {
    try {
      final live = await fetchLive(code);
      if (live == null || !live.isValid) return null;
      await cacheVerifyResult(live);
      return live;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearEvent() async {
    _cachedCode = '';
    _cachedPhotoMode = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefsEventCode);
    await prefs.remove(_kPrefsEventId);
    await prefs.remove(_kPrefsEventPhotoMode);
    await prefs.remove(_kPrefsEventThemeCount);
    await prefs.remove(_kPrefsEventFrameCount);
    await prefs.remove(_kPrefsEventName);
    await prefs.remove(_kPrefsEventJson);
    await prefs.remove(_kPrefsStationRole);
    _cachedStationRole = '';
  }
}
