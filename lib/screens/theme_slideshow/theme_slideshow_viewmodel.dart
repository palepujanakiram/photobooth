import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/theme_manager.dart';
import '../../utils/exceptions.dart';
import '../../utils/app_config.dart';
import '../theme_selection/theme_model.dart';

class ThemeSlideshowViewModel extends ChangeNotifier {
  final ThemeManager _themeManager;
  List<ThemeModel> _themes = [];
  bool _isLoading = true;
  bool _isPreloadingImages = false;
  String? _errorMessage;
  List<String> _preloadedImageUrls = [];
  VoidCallback? _themeManagerListener;

  ThemeSlideshowViewModel({ThemeManager? themeManager})
      : _themeManager = themeManager ?? ThemeManager() {
    // Listen to ThemeManager updates
    _themeManagerListener = _themeManager.addListener(_onThemesUpdated);
  }

  @override
  void dispose() {
    // Remove listener when ViewModel is disposed
    if (_themeManagerListener != null) {
      _themeManager.removeListener(_themeManagerListener!);
    }
    super.dispose();
  }

  List<ThemeModel> get themes => _themes;
  bool get isLoading => _isLoading;
  bool get isPreloadingImages => _isPreloadingImages;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;
  List<String> get preloadedImageUrls => _preloadedImageUrls;

  /// Called when ThemeManager updates themes
  void _onThemesUpdated() {
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

  /// Preloads all images asynchronously
  /// Handles individual image failures gracefully
  Future<void> preloadImages(BuildContext context) async {
    final imageUrls = getSampleImageUrls();
    if (imageUrls.isEmpty) {
      _preloadedImageUrls = [];
      notifyListeners();
      return;
    }

    _isPreloadingImages = true;
    _preloadedImageUrls = [];
    notifyListeners();

    try {
      // Preload all images in parallel with individual error handling
      final preloadFutures = imageUrls.map((url) async {
        try {
          // Add timeout to prevent hanging on connection errors
          await precacheImage(
            NetworkImage(url),
            context,
          ).timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              debugPrint('Image preload timeout for: $url');
              throw TimeoutException('Image preload timeout', const Duration(seconds: 10));
            },
          );
          return url; // Return URL if successful
        } catch (e) {
          // Log error but don't fail the entire preload
          debugPrint('Failed to preload image: $url - Error: $e');
          return null; // Return null for failed images
        }
      }).toList();

      // Wait for all preload attempts (some may fail)
      final results = await Future.wait(preloadFutures);
      
      // Only keep successfully preloaded images
      _preloadedImageUrls = results.whereType<String>().toList();
      
      // If we have at least some images, use them. Otherwise, use all URLs
      // (they might still load when displayed)
      if (_preloadedImageUrls.isEmpty && imageUrls.isNotEmpty) {
        _preloadedImageUrls = imageUrls;
        debugPrint('No images preloaded successfully, but will attempt to display them');
      }
      
      _isPreloadingImages = false;
      notifyListeners();
    } catch (e) {
      // Fallback: use all URLs even if preload failed
      // They might still load when displayed
      debugPrint('Error during image preloading: $e');
      _preloadedImageUrls = imageUrls;
      _isPreloadingImages = false;
      notifyListeners();
    }
  }
}

