import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import '../../services/theme_manager.dart';
import '../../services/image_cache_service.dart';
import '../../utils/exceptions.dart';
import '../../utils/logger.dart';
import '../../utils/theme_image_urls.dart';
import '../theme_selection/theme_model.dart';

class ThemeSlideshowViewModel extends ChangeNotifier {
  final ThemeManager _themeManager;
  final ImageCacheService _imageCacheService;
  List<ThemeModel> _themes = [];
  bool _isLoading = true;
  bool _isPreloadingImages = false;
  bool _isFirstImageLoaded = false;
  bool _areAllImagesLoaded = false;
  String? _errorMessage;
  List<String> _preloadedImageUrls = [];
  VoidCallback? _themeManagerListener;
  bool _isDisposed = false;

  ThemeSlideshowViewModel(
      {ThemeManager? themeManager, ImageCacheService? imageCacheService})
      : _themeManager = themeManager ?? ThemeManager(),
        _imageCacheService = imageCacheService ?? ImageCacheService() {
    // Listen to ThemeManager updates
    _themeManagerListener = _themeManager.addListener(_onThemesUpdated);
  }

  @override
  void dispose() {
    _isDisposed = true;
    // Remove listener when ViewModel is disposed
    if (_themeManagerListener != null) {
      _themeManager.removeListener(_themeManagerListener!);
    }
    super.dispose();
  }

  /// Safe notifyListeners that checks if disposed
  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  List<ThemeModel> get themes => _themes;
  bool get isLoading => _isLoading;
  bool get isPreloadingImages => _isPreloadingImages;
  bool get isFirstImageLoaded => _isFirstImageLoaded;
  bool get areAllImagesLoaded => _areAllImagesLoaded;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;
  List<String> get preloadedImageUrls => _preloadedImageUrls;

  /// Gets the theme for a given image URL
  /// Returns null if no matching theme is found
  ThemeModel? getThemeForImageUrl(String imageUrl) {
    if (imageUrl.isEmpty || _themes.isEmpty) {
      return null;
    }

    // Get active themes with sample images
    final activeThemes = _themes
        .where((theme) =>
            (theme.isActive == true) &&
            theme.sampleImageUrl != null &&
            theme.sampleImageUrl!.isNotEmpty)
        .toList();

    if (activeThemes.isEmpty) {
      return null;
    }

    for (final theme in activeThemes) {
      final fullThemeUrl =
          resolveThemeSampleImageUrl(theme.sampleImageUrl!);
      final normalizedThemeUrl = normalizeThemeImageUrl(fullThemeUrl);
      final normalizedImageUrl = normalizeThemeImageUrl(imageUrl);

      if (normalizedImageUrl == normalizedThemeUrl ||
          normalizedImageUrl.contains(normalizedThemeUrl) ||
          normalizedThemeUrl.contains(normalizedImageUrl)) {
        return theme;
      }
    }

    return null;
  }

  /// Called when ThemeManager updates themes
  void _onThemesUpdated() {
    if (_isDisposed) return;
    _themes = _themeManager.themes;
    _isLoading = _themeManager.isLoading;
    _errorMessage = _themeManager.errorMessage;
    notifyListeners();
  }

  /// Fetches themes using ThemeManager
  /// [forceRefresh] - If true, forces a fresh fetch from API
  Future<void> fetchThemes({bool forceRefresh = false}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Fetch themes from ThemeManager (will use cache if available)
      await _themeManager.fetchThemes(forceRefresh: forceRefresh);
      // Update local state from ThemeManager
      _onThemesUpdated();
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      // If ThemeManager has cached themes, use them
      if (_themeManager.hasThemes) {
        _onThemesUpdated();
      } else {
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = 'Failed to fetch themes: $e';
      _isLoading = false;
      // If ThemeManager has cached themes, use them
      if (_themeManager.hasThemes) {
        _onThemesUpdated();
      } else {
        notifyListeners();
      }
    }
  }

  /// Gets all sample image URLs from active themes with base URL prepended
  List<String> getSampleImageUrls() {
    return _themes
        .where((theme) =>
            (theme.isActive == true) &&
            theme.sampleImageUrl != null &&
            theme.sampleImageUrl!.isNotEmpty)
        .map((theme) {
          final fullUrl = resolveThemeSampleImageUrl(theme.sampleImageUrl!);
          if (isValidHttpUrl(fullUrl)) {
            return fullUrl;
          }
          AppLogger.debug('Invalid theme sample URL: $fullUrl');
          return null;
        })
        .whereType<String>() // Filter out null values
        .toList();
  }

  /// Preloads images with priority: first image first, then rest
  /// Handles individual image failures gracefully
  Future<void> preloadImages(BuildContext context) async {
    if (_isDisposed) return;

    final imageUrls = getSampleImageUrls();
    if (imageUrls.isEmpty) {
      if (_isDisposed) return;
      _preloadedImageUrls = [];
      _isFirstImageLoaded = false;
      _areAllImagesLoaded = false;
      notifyListeners();
      return;
    }

    if (_isDisposed) return;
    _isPreloadingImages = true;
    _isFirstImageLoaded = false;
    _areAllImagesLoaded = false;
    _preloadedImageUrls = [];
    notifyListeners();

    try {
      if (imageUrls.isNotEmpty && !_isDisposed) {
        await _preloadFirstSlideshowImage(context, imageUrls[0]);
      }
      if (!context.mounted || _isDisposed) return;
      if (imageUrls.length > 1) {
        await _preloadRemainingSlideshowImages(context, imageUrls);
      }

      if (_isDisposed) return;

      _areAllImagesLoaded = true;
      _isPreloadingImages = false;
      notifyListeners();
    } catch (e) {
      if (_isDisposed) return;
      // Fallback: use all URLs even if preload failed
      AppLogger.debug('Error during image preloading: $e');
      _preloadedImageUrls = imageUrls;
      _isFirstImageLoaded = imageUrls.isNotEmpty;
      _areAllImagesLoaded = true; // Mark as done so animation can start
      _isPreloadingImages = false;
      notifyListeners();
    }
  }

  /// Cache + precache index 0 so the slideshow can start animating ASAP.
  Future<void> _preloadFirstSlideshowImage(
    BuildContext context,
    String url,
  ) async {
    try {
      final cachedFile = await _cacheWithTimeout(url, label: 'First image');
      if (_isDisposed || !context.mounted) return;
      await _precacheSlideshowUrl(context, url, cachedFile);
      _markFirstImageReady(url);
    } catch (e) {
      if (_isDisposed) return;
      AppLogger.debug('Failed to cache/preload first image: $url - Error: $e');
      _markFirstImageReady(url);
    }
  }

  /// Parallel preload for slides 1..n; keeps first URL even if later frames fail.
  Future<void> _preloadRemainingSlideshowImages(
    BuildContext context,
    List<String> imageUrls,
  ) async {
    final remainingUrls = imageUrls.sublist(1);
    final results = await Future.wait(
      remainingUrls.map((url) => _preloadOneSlideshowImage(context, url)),
    );
    if (_isDisposed) return;

    final successfulUrls = results.whereType<String>().toList();
    _preloadedImageUrls = [imageUrls[0], ...successfulUrls];
    if (successfulUrls.length < remainingUrls.length) {
      final failedUrls = remainingUrls
          .where((u) => !successfulUrls.contains(u))
          .toList();
      _preloadedImageUrls = [..._preloadedImageUrls, ...failedUrls];
    }
  }

  Future<String?> _preloadOneSlideshowImage(
    BuildContext context,
    String url,
  ) async {
    if (_isDisposed) return null;
    try {
      final cachedFile = await _cacheWithTimeout(url);
      if (!context.mounted) return null;
      await _precacheSlideshowUrl(context, url, cachedFile);
      return url;
    } catch (e) {
      AppLogger.debug('Failed to cache/preload image: $url - Error: $e');
      return null;
    }
  }

  Future<dynamic> _cacheWithTimeout(String url, {String? label}) {
    return _imageCacheService.cacheImage(url).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        AppLogger.debug('${label ?? 'Image'} cache timeout for: $url');
        throw TimeoutException(
          '${label ?? 'Image'} cache timeout',
          const Duration(seconds: 10),
        );
      },
    );
  }

  Future<void> _precacheSlideshowUrl(
    BuildContext context,
    String url,
    File? cachedFile,
  ) async {
    try {
      if (cachedFile == null) {
        await precacheImage(NetworkImage(url), context).timeout(
          const Duration(seconds: 10),
        );
      } else {
        await precacheImage(FileImage(cachedFile), context).timeout(
          const Duration(seconds: 10),
        );
      }
    } catch (e) {
      AppLogger.debug('Precache failed for $url: $e');
    }
  }

  void _markFirstImageReady(String url) {
    _isFirstImageLoaded = true;
    _preloadedImageUrls = [url];
    notifyListeners();
  }
}
