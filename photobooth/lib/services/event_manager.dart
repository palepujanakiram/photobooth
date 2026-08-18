import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

/// Cached booth event from `/api/event/verify` (additive to [KioskManager]).
class EventManager {
  static const String _kPrefsEventCode = 'event_code';
  static const String _kPrefsEventId = 'event_id';
  static const String _kPrefsEventPhotoMode = 'event_photo_mode';
  static const String _kPrefsEventThemeCount = 'event_theme_count';
  static const String _kPrefsEventFrameCount = 'event_frame_count';
  static const String _kPrefsEventName = 'event_name';

  static String? _cachedCode;
  static String? _cachedPhotoMode;

  @visibleForTesting
  static void resetCacheForTests() {
    _cachedCode = null;
    _cachedPhotoMode = null;
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

  Future<void> cacheVerifyResult({
    required String id,
    required String code,
    required String photoMode,
    String? name,
    int themeCount = 0,
    int frameCount = 0,
  }) async {
    await setEventCode(code);
    await setPhotoModeOverride(photoMode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsEventId, id);
    if (name != null && name.trim().isNotEmpty) {
      await prefs.setString(_kPrefsEventName, name.trim());
    } else {
      await prefs.remove(_kPrefsEventName);
    }
    await prefs.setInt(_kPrefsEventThemeCount, themeCount);
    await prefs.setInt(_kPrefsEventFrameCount, frameCount);
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
  }
}
