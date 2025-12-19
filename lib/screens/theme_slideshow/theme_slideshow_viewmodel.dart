import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../utils/exceptions.dart';
import '../../utils/app_config.dart';
import '../theme_selection/theme_model.dart';

class ThemeSlideshowViewModel extends ChangeNotifier {
  final ApiService _apiService;
  List<ThemeModel> _themes = [];
  bool _isLoading = true;
  bool _isPreloadingImages = false;
  String? _errorMessage;
  List<String> _preloadedImageUrls = [];

  ThemeSlideshowViewModel({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  List<ThemeModel> get themes => _themes;
  bool get isLoading => _isLoading;
  bool get isPreloadingImages => _isPreloadingImages;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;
  List<String> get preloadedImageUrls => _preloadedImageUrls;

  /// Fetches themes from the API
  Future<void> fetchThemes() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _themes = await _apiService.getThemes();
      _isLoading = false;
      notifyListeners();
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to fetch themes: $e';
      _isLoading = false;
      notifyListeners();
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
          final imageUrl = theme.sampleImageUrl!;
          // Check if URL is already absolute
          if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
            return imageUrl;
          }
          // Prepend base URL if it's a relative path
          final baseUrl = AppConfig.baseUrl.endsWith('/')
              ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
              : AppConfig.baseUrl;
          final relativePath = imageUrl.startsWith('/') ? imageUrl : '/$imageUrl';
          return '$baseUrl$relativePath';
        })
        .toList();
  }

  /// Preloads all images asynchronously
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
      // Preload all images in parallel
      final preloadFutures = imageUrls.map((url) {
        return precacheImage(NetworkImage(url), context);
      }).toList();

      await Future.wait(preloadFutures);
      
      _preloadedImageUrls = imageUrls;
      _isPreloadingImages = false;
      notifyListeners();
    } catch (e) {
      // Even if some images fail to preload, we'll still show what we can
      _preloadedImageUrls = imageUrls;
      _isPreloadingImages = false;
      notifyListeners();
    }
  }
}

