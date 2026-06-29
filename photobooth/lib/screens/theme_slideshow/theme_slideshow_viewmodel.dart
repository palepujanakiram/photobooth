import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import '../../services/theme_manager.dart';
import '../../services/image_cache_service.dart';
import '../../utils/logger.dart';
import '../../utils/error_reporting_helpers.dart';
import '../../utils/theme_image_urls.dart';
import '../../views/widgets/animated_slideshow_background.dart'
    show kSlideshowAssetPaths;
import '../theme_selection/theme_model.dart';
import 'theme_slideshow_image.dart';

class ThemeSlideshowViewModel extends ChangeNotifier {
  final ThemeManager _themeManager;
  final ImageCacheService _imageCacheService;
  List<ThemeModel> _themes = [];
  final bool _isLoading = false;
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

  /// Called when ThemeManager updates themes (slideshow UI stays on bundled assets).
  void _onThemesUpdated() {
    if (_isDisposed) return;
    _themes = _themeManager.themes;
    notifyListeners();
  }

  /// Warms [ThemeManager] for later screens; slideshow UI uses bundled assets.
  /// [forceRefresh] - If true, forces a fresh fetch from API
  Future<void> fetchThemes({bool forceRefresh = false}) async {
    try {
      await _themeManager.fetchThemes(forceRefresh: forceRefresh);
      _onThemesUpdated();
    } catch (e, st) {
      unawaited(
        reportIssue(
          'Background theme prefetch failed',
          e,
          st,
          extraInfo: {'source': 'theme_slideshow_prefetch'},
        ),
      );
      if (_themeManager.hasThemes) {
        _onThemesUpdated();
      }
    }
  }

  /// Slideshow frames: local assets for instant display (not theme API samples).
  List<String> getSampleImageUrls() {
    return List<String>.from(kSlideshowAssetPaths);
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
    } catch (e, st) {
      if (_isDisposed) return;
      unawaited(
        reportIssue(
          'Slideshow image preload failed',
          e,
          st,
          extraInfo: {'source': 'theme_slideshow_preload'},
        ),
      );
      // Fallback: use all URLs even if preload failed
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
      if (_isDisposed || !context.mounted) return;
      await _precacheSlideshowPath(context, url);
      _markFirstImageReady(url);
    } catch (e) {
      if (_isDisposed) return;
      AppLogger.debug('Failed to preload first slideshow image: $url - $e');
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
      if (!context.mounted) return null;
      await _precacheSlideshowPath(context, url);
      return url;
    } catch (e) {
      AppLogger.debug('Failed to preload slideshow image: $url - $e');
      return null;
    }
  }

  Future<void> _precacheSlideshowPath(BuildContext context, String path) async {
    if (isSlideshowAssetImagePath(path)) {
      await precacheImage(AssetImage(path), context).timeout(
        const Duration(seconds: 5),
      );
      return;
    }
    final cachedFile = await _cacheWithTimeout(path, label: 'Slideshow image');
    if (!context.mounted) return;
    await _precacheSlideshowUrl(context, path, cachedFile);
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
