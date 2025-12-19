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
        name: 'Vintage',
        description: 'Classic vintage photo effect with warm tones',
        prompt: 'oil painting style',
        negativePrompt: 'blurry, low quality',
      ),
      const ThemeModel(
        id: '2',
        name: 'Black & White',
        description: 'Timeless black and white photography',
        prompt: 'oil painting style',
        negativePrompt: 'blurry, low quality',
      ),
      const ThemeModel(
        id: '3',
        name: 'Portrait',
        description: 'Professional portrait enhancement',
        prompt: 'oil painting style',
        negativePrompt: 'blurry, low quality',
      ),
      const ThemeModel(
        id: '4',
        name: 'Artistic',
        description: 'Creative artistic transformation',
        prompt: 'oil painting style',
        negativePrompt: 'blurry, low quality',
      ),
      const ThemeModel(
        id: '5',
        name: 'Nature',
        description: 'Natural outdoor enhancement',
        prompt: 'oil painting style',
        negativePrompt: 'blurry, low quality',
      ),
      const ThemeModel(
        id: '6',
        name: 'Cinematic',
        description: 'Movie-like cinematic effect',
        prompt: 'oil painting style',
        negativePrompt: 'blurry, low quality',
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

