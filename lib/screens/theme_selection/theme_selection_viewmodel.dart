import 'package:flutter/foundation.dart';
import 'theme_model.dart';
import '../../services/api_service.dart';
import '../../utils/exceptions.dart';

class ThemeViewModel extends ChangeNotifier {
  final ApiService _apiService;
  List<ThemeModel> _themes = [];
  ThemeModel? _selectedTheme;
  bool _isLoading = false;
  String? _errorMessage;

  ThemeViewModel({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  List<ThemeModel> get themes => _themes;
  ThemeModel? get selectedTheme => _selectedTheme;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;

  /// Loads themes from the API
  Future<void> loadThemes() async {
    _setLoading(true);
    _errorMessage = null;

    try {
      _themes = await _apiService.getThemes();
      notifyListeners();
    } on ApiException {
      _themes = _getMockThemes();
      notifyListeners();
    } catch (e) {
      // If any other error, use mock themes for development
      _themes = _getMockThemes();
      _errorMessage = null;
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  /// Returns mock themes for development/demo purposes
  List<ThemeModel> _getMockThemes() {
    return [
      const ThemeModel(
        id: '1',
        categoryId: 'cat-1',
        name: 'Vintage',
        description: 'Classic vintage photo effect with warm tones',
        promptText: 'oil painting style',
        negativePrompt: 'blurry, low quality',
        sampleImageUrl: 'https://images.unsplash.com/photo-1515886657613-9f3515b0c78f?w=800&h=600&fit=crop',
        isActive: true,
      ),
      const ThemeModel(
        id: '2',
        categoryId: 'cat-1',
        name: 'Black & White',
        description: 'Timeless black and white photography',
        promptText: 'oil painting style',
        negativePrompt: 'blurry, low quality',
        sampleImageUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=800&h=600&fit=crop',
        isActive: true,
      ),
      const ThemeModel(
        id: '3',
        categoryId: 'cat-1',
        name: 'Portrait',
        description: 'Professional portrait enhancement',
        promptText: 'oil painting style',
        negativePrompt: 'blurry, low quality',
        sampleImageUrl: 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=800&h=600&fit=crop',
        isActive: true,
      ),
      const ThemeModel(
        id: '4',
        categoryId: 'cat-1',
        name: 'Artistic',
        description: 'Creative artistic transformation',
        promptText: 'oil painting style',
        negativePrompt: 'blurry, low quality',
        sampleImageUrl: 'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=800&h=600&fit=crop',
        isActive: true,
      ),
      const ThemeModel(
        id: '5',
        categoryId: 'cat-1',
        name: 'Nature',
        description: 'Natural outdoor enhancement',
        promptText: 'oil painting style',
        negativePrompt: 'blurry, low quality',
        sampleImageUrl: 'https://images.unsplash.com/photo-1515886657613-9f3515b0c78f?w=800&h=600&fit=crop',
        isActive: true,
      ),
      const ThemeModel(
        id: '6',
        categoryId: 'cat-1',
        name: 'Cinematic',
        description: 'Movie-like cinematic effect',
        promptText: 'oil painting style',
        negativePrompt: 'blurry, low quality',
        sampleImageUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=800&h=600&fit=crop',
        isActive: true,
      ),
    ];
  }

  /// Selects a theme
  void selectTheme(ThemeModel theme) {
    _selectedTheme = theme;
    _errorMessage = null;
    notifyListeners();
  }

  /// Clears the selected theme
  void clearSelection() {
    _selectedTheme = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}

