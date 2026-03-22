import 'package:flutter/foundation.dart';
import '../screens/theme_selection/theme_model.dart';
import '../utils/exceptions.dart';
import '../utils/app_config.dart';
import 'api_service.dart';

/// Singleton class responsible for fetching, caching, and providing themes
/// to all screens that need them.
class ThemeManager {
  // Private constructor for singleton pattern
  ThemeManager._internal();

  // Singleton instance
  static final ThemeManager _instance = ThemeManager._internal();

  /// Get the singleton instance
  factory ThemeManager() => _instance;

  final ApiService _apiService = ApiService();

  // Cached themes
  List<ThemeModel> _cachedThemes = [];
  
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
    // Return cached themes if available and not forcing refresh
    if (!forceRefresh && _cachedThemes.isNotEmpty && !_isLoading) {
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
      _lastFetchTime = DateTime.now();
      _errorMessage = null;
      _isLoading = false;
      _notifyListeners();
      return List.unmodifiable(_cachedThemes);
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      _notifyListeners();
      if (_cachedThemes.isNotEmpty) {
        return List.unmodifiable(_cachedThemes);
      }
      rethrow;
    } catch (e) {
      _errorMessage = 'Failed to fetch themes: $e';
      _isLoading = false;
      _notifyListeners();
      if (_cachedThemes.isNotEmpty) {
        return List.unmodifiable(_cachedThemes);
      }
      throw ApiException('Failed to fetch themes: $e');
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
    final list = _cachedThemes.where((theme) => theme.isActive != false).toList();
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
          final imageUrl = theme.sampleImageUrl!.trim();
          // Check if URL is already absolute
          if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
            // Validate URL format
            try {
              Uri.parse(imageUrl);
              return imageUrl;
            } catch (e) {
              debugPrint('Invalid absolute URL format: $imageUrl');
              return null;
            }
          }
          // Prepend base URL if it's a relative path
          final baseUrl = AppConfig.baseUrl.endsWith('/')
              ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
              : AppConfig.baseUrl;
          final relativePath = imageUrl.startsWith('/') ? imageUrl : '/$imageUrl';
          final fullUrl = '$baseUrl$relativePath';
          // Validate constructed URL
          try {
            Uri.parse(fullUrl);
            return fullUrl;
          } catch (e) {
            debugPrint('Invalid constructed URL format: $fullUrl');
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
      } catch (e) {
        // Ignore errors from listeners
        debugPrint('Error in ThemeManager listener: $e');
      }
    }
  }
}

