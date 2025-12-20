import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/theme_manager.dart';
import '../../services/image_cache_service.dart';
import '../../utils/exceptions.dart';
import '../../utils/app_config.dart';
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

  ThemeSlideshowViewModel({ThemeManager? themeManager, ImageCacheService? imageCacheService})
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
            theme.isActive && 
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
      // Step 1: Load first image immediately (cache it)
      if (imageUrls.isNotEmpty && !_isDisposed) {
        try {
          // Cache the first image
          final cachedFile = await _imageCacheService.cacheImage(imageUrls[0]).timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              debugPrint('First image cache timeout');
              throw TimeoutException('First image cache timeout', const Duration(seconds: 10));
            },
          );
          
          if (_isDisposed) return;
          
          // Also precache for immediate display
          // Note: In ViewModel, we use the context passed to the method
          // The context is captured at the method call site, so it's safe to use
          try {
            if (cachedFile == null) {
              await precacheImage(NetworkImage(imageUrls[0]), context).timeout(
                const Duration(seconds: 10),
              );
            } else {
              // Precache the cached file
              await precacheImage(FileImage(cachedFile), context).timeout(
                const Duration(seconds: 10),
              );
            }
          } catch (e) {
            // Precache failure is not critical - image will load when displayed
            debugPrint('Precache failed for first image: $e');
          }
          
          _isFirstImageLoaded = true;
          _preloadedImageUrls = [imageUrls[0]];
          notifyListeners();
        } catch (e) {
          if (_isDisposed) return;
          debugPrint('Failed to cache/preload first image: ${imageUrls[0]} - Error: $e');
          // Continue anyway - image might still load when displayed
          _isFirstImageLoaded = true;
          _preloadedImageUrls = [imageUrls[0]];
          notifyListeners();
        }
      }

      // Step 2: Cache and preload remaining images in parallel
      if (imageUrls.length > 1 && !_isDisposed) {
        // Capture context before async operations
        final currentContext = context;
        final remainingUrls = imageUrls.sublist(1);
        final preloadFutures = remainingUrls.map((url) async {
          if (_isDisposed) return null;
          try {
            // Cache the image first
            final cachedFile = await _imageCacheService.cacheImage(url).timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                debugPrint('Image cache timeout for: $url');
                throw TimeoutException('Image cache timeout', const Duration(seconds: 10));
              },
            );
            
            // Precache for immediate display
            // Note: precacheImage doesn't require mounted check, context is captured before async
            try {
              if (cachedFile != null) {
                await precacheImage(FileImage(cachedFile), currentContext).timeout(
                  const Duration(seconds: 10),
                );
              } else {
                // Fallback to network precache
                await precacheImage(NetworkImage(url), currentContext).timeout(
                  const Duration(seconds: 10),
                );
              }
            } catch (e) {
              // Precache failure is not critical - image will load when displayed
              debugPrint('Precache failed for $url: $e');
            }
            
            return url; // Return URL if successful
          } catch (e) {
            // Log error but don't fail the entire preload
            debugPrint('Failed to cache/preload image: $url - Error: $e');
            return null; // Return null for failed images
          }
        }).toList();

        // Wait for all remaining images to preload
        final results = await Future.wait(preloadFutures);
        
        if (_isDisposed) return;
        
        // Add successfully preloaded images to the list
        final successfulUrls = results.whereType<String>().toList();
        _preloadedImageUrls = [imageUrls[0], ...successfulUrls];
        
        // If some images failed, still include them (they might load when displayed)
        if (successfulUrls.length < remainingUrls.length) {
          final failedUrls = remainingUrls.where((url) => !successfulUrls.contains(url)).toList();
          _preloadedImageUrls = [..._preloadedImageUrls, ...failedUrls];
        }
      }
      
      if (_isDisposed) return;
      
      _areAllImagesLoaded = true;
      _isPreloadingImages = false;
      notifyListeners();
    } catch (e) {
      if (_isDisposed) return;
      // Fallback: use all URLs even if preload failed
      debugPrint('Error during image preloading: $e');
      _preloadedImageUrls = imageUrls;
      _isFirstImageLoaded = imageUrls.isNotEmpty;
      _areAllImagesLoaded = true; // Mark as done so animation can start
      _isPreloadingImages = false;
      notifyListeners();
    }
  }
}

