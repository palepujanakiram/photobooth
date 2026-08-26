import 'dart:async';

import 'package:flutter/foundation.dart' show VoidCallback, visibleForTesting;
import '../screens/theme_selection/theme_model.dart';
import '../utils/exceptions.dart';
import '../utils/theme_image_urls.dart';
import '../utils/error_reporting_helpers.dart';
import '../utils/logger.dart';
import 'api_service.dart';
import 'catalog_disk_cache.dart';
import 'image_cache_service.dart';
import 'image_cache_source.dart';
import 'kiosk_manager.dart';
import 'event_manager.dart';

/// Singleton class responsible for fetching, caching, and providing themes
/// to all screens that need them.
class ThemeManager {
  ThemeManager._internal([
    ApiService? apiService,
    CatalogDiskCache? diskCache,
    ImageCacheService? imageCache,
  ])  : _apiService = apiService ?? ApiService(),
        _diskCache = diskCache,
        _imageCache = imageCache;

  static final ThemeManager _instance = ThemeManager._internal(
    null,
    CatalogDiskCache(),
    ImageCacheService(),
  );

  /// Get the singleton instance
  factory ThemeManager() => _instance;

  /// Non-singleton instance for unit tests.
  @visibleForTesting
  factory ThemeManager.forTesting(
    ApiService apiService, {
    CatalogDiskCache? diskCache,
  }) =>
      ThemeManager._internal(apiService, diskCache);

  final ApiService _apiService;
  final CatalogDiskCache? _diskCache;
  final ImageCacheService? _imageCache;

  // Cached themes
  List<ThemeModel> _cachedThemes = [];
  String _cachedThemesKioskKey = '';

  // Loading state
  bool _isLoading = false;
  Future<List<ThemeModel>>? _ongoingFetch;

  // Error state
  String? _errorMessage;

  // Timestamp of last fetch
  DateTime? _lastFetchTime;

  // Listeners for theme updates
  final List<VoidCallback> _listeners = [];

  /// Get cached themes (returns empty list if not fetched yet)
  List<ThemeModel> get themes => List.unmodifiable(_cachedThemes);

  /// Check if themes are currently being loaded
  bool get isLoading => _isLoading;

  /// Get error message if any
  String? get errorMessage => _errorMessage;

  /// Check if there's an error
  bool get hasError => _errorMessage != null;

  /// Check if themes have been fetched at least once
  bool get hasThemes => _cachedThemes.isNotEmpty;

  /// Get timestamp of last successful fetch
  DateTime? get lastFetchTime => _lastFetchTime;

  /// Fetches themes from the API and caches them.
  /// If themes are already cached and [forceRefresh] is false,
  /// returns cached themes without making an API call.
  ///
  /// [forceRefresh] - If true, forces a fresh fetch from API
  /// Returns the list of themes (cached or freshly fetched)
  Future<List<ThemeModel>> fetchThemes({bool forceRefresh = false}) async {
    // Invalidate cache automatically when kiosk changes.
    final kioskCode = await KioskManager().getKioskCode();
    final eventCode = await EventManager().getEventCode();
    final kioskKey = '${(kioskCode ?? '').trim()}|${(eventCode ?? '').trim()}';
    if (_cachedThemes.isNotEmpty && _cachedThemesKioskKey != kioskKey) {
      _cachedThemes = [];
      _lastFetchTime = null;
      _errorMessage = null;
      _cachedThemesKioskKey = kioskKey;
    }

    if (_cachedThemes.isEmpty) {
      await _hydrateFromDisk(kioskKey);
    }

    // Return cached themes if available and not forcing refresh
    if (!forceRefresh &&
        _cachedThemes.isNotEmpty &&
        _lastFetchTime != null &&
        !_isLoading) {
      return List.unmodifiable(_cachedThemes);
    }

    // If a request is already in progress, reuse it instead of polling.
    if (_ongoingFetch != null) {
      return _ongoingFetch!;
    }

    final fetchFuture = _fetchThemesInternal();
    _ongoingFetch = fetchFuture;
    try {
      return await fetchFuture;
    } finally {
      _ongoingFetch = null;
    }
  }

  Future<List<ThemeModel>> _fetchThemesInternal() async {
    _isLoading = true;
    _errorMessage = null;
    _notifyListeners();

    try {
      final themes = await _apiService.getThemes();
      _cachedThemes = themes;
      final kioskCode = await KioskManager().getKioskCode();
      final eventCode = await EventManager().getEventCode();
      _cachedThemesKioskKey =
          '${(kioskCode ?? '').trim()}|${(eventCode ?? '').trim()}';
      _lastFetchTime = DateTime.now();
      _errorMessage = null;
      _isLoading = false;
      _notifyListeners();
      await _persistToDisk(_cachedThemesKioskKey);
      unawaited(_precacheThemeImages(themes));
      return List.unmodifiable(_cachedThemes);
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      _notifyListeners();
      if (_cachedThemes.isNotEmpty) {
        return List.unmodifiable(_cachedThemes);
      }
      rethrow;
    } catch (e, st) {
      _errorMessage = 'Failed to fetch themes: $e';
      unawaited(
        reportIssue(
          'Failed to fetch themes',
          e,
          st,
          extraInfo: {'source': 'theme_manager'},
        ),
      );
      _isLoading = false;
      _notifyListeners();
      if (_cachedThemes.isNotEmpty) {
        return List.unmodifiable(_cachedThemes);
      }
      throw ApiException('Failed to fetch themes: $e');
    }
  }

  String _diskKey(String kioskKey) {
    final safe = kioskKey.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return 'themes_${safe.isEmpty ? 'default' : safe}';
  }

  Future<void> _hydrateFromDisk(String kioskKey) async {
    final disk = _diskCache;
    if (disk == null || _cachedThemes.isNotEmpty) return;
    final raw = await disk.readJson(_diskKey(kioskKey));
    if (raw is! List) return;
    final loaded = <ThemeModel>[];
    for (final row in raw) {
      if (row is! Map) continue;
      final theme = ThemeModel.fromJson(Map<String, dynamic>.from(row));
      if (theme.id.isNotEmpty) loaded.add(theme);
    }
    if (loaded.isEmpty) return;
    _cachedThemes = loaded;
    _cachedThemesKioskKey = kioskKey;
  }

  Future<void> _persistToDisk(String kioskKey) async {
    final disk = _diskCache;
    if (disk == null) return;
    await disk.writeJson(
      _diskKey(kioskKey),
      _cachedThemes.map((t) => t.toJson()).toList(),
    );
  }

  Future<void> _precacheThemeImages(Iterable<ThemeModel> themes) async {
    final cache = _imageCache;
    if (cache == null) return;
    for (final theme in themes) {
      final url = theme.sampleImageUrl?.trim() ?? '';
      if (url.isEmpty) continue;
      await cache.cacheImage(
        resolveThemeSampleImageUrl(url),
        cacheKey: catalogCacheKeyForTheme(theme.id),
      );
    }
  }

  /// Gets themes synchronously from cache.
  /// Returns empty list if themes haven't been fetched yet.
  /// Use [fetchThemes()] to ensure themes are loaded.
  List<ThemeModel> getThemes() {
    return List.unmodifiable(_cachedThemes);
  }

  /// Gets a theme by ID from cache.
  /// Returns null if theme is not found.
  ThemeModel? getThemeById(String id) {
    try {
      return _cachedThemes.firstWhere((theme) => theme.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Gets themes for display: filter by isActive when present (show only when true),
  /// sort by displayOrder ascending when present (nulls last).
  List<ThemeModel> getActiveThemes() {
    final list =
        _cachedThemes.where((theme) => theme.isActive != false).toList();
    list.sort((a, b) {
      final aOrder = a.displayOrder;
      final bOrder = b.displayOrder;
      if (aOrder == null && bOrder == null) return 0;
      if (aOrder == null) return 1;
      if (bOrder == null) return -1;
      return aOrder.compareTo(bOrder);
    });
    return list;
  }

  /// Gets all sample image URLs from active themes with base URL prepended.
  /// Returns empty list if no themes are available.
  List<String> getSampleImageUrls() {
    return _cachedThemes
        .where((theme) =>
            (theme.isActive == true) &&
            theme.sampleImageUrl != null &&
            theme.sampleImageUrl!.isNotEmpty)
        .map((theme) {
          final fullUrl = resolveThemeSampleImageUrl(theme.sampleImageUrl!);
          try {
            Uri.parse(fullUrl);
            return fullUrl;
          } catch (e) {
            AppLogger.debug('Invalid theme sample image URL: $fullUrl');
            return null;
          }
        })
        .whereType<String>() // Filter out null values
        .toList();
  }

  /// Clears the cached themes.
  /// Useful for logout or when you want to force a fresh fetch.
  void clearCache() {
    _cachedThemes = [];
    _errorMessage = null;
    _lastFetchTime = null;
    _notifyListeners();
  }

  /// Adds a listener that will be called whenever themes are updated.
  /// Returns a function to remove the listener.
  VoidCallback addListener(VoidCallback listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// Removes a listener.
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// Notifies all listeners of changes.
  void _notifyListeners() {
    for (final listener in _listeners) {
      try {
        listener();
      } catch (e, st) {
        // Ignore errors from listeners
        AppLogger.error('Error in ThemeManager listener',
            error: e, stackTrace: st);
      }
    }
  }
}
