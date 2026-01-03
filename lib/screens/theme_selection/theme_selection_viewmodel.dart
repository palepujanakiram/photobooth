import 'package:flutter/foundation.dart';
import 'theme_model.dart';
import '../../services/theme_manager.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../utils/exceptions.dart';

class ThemeViewModel extends ChangeNotifier {
  final ThemeManager _themeManager;
  final ApiService _apiService;
  final SessionManager _sessionManager;
  List<ThemeModel> _themes = [];
  ThemeModel? _selectedTheme;
  bool _isLoading = false;
  bool _isUpdatingSession = false;
  String? _errorMessage;
  VoidCallback? _themeManagerListener;

  ThemeViewModel({
    ThemeManager? themeManager,
    ApiService? apiService,
    SessionManager? sessionManager,
  })  : _themeManager = themeManager ?? ThemeManager(),
        _apiService = apiService ?? ApiService(),
        _sessionManager = sessionManager ?? SessionManager() {
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
  ThemeModel? get selectedTheme => _selectedTheme;
  bool get isLoading => _isLoading;
  bool get isUpdatingSession => _isUpdatingSession;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;

  /// Called when ThemeManager updates themes
  /// Made public so view can call it to use cached themes immediately
  void _onThemesUpdated() {
    _themes = _themeManager.getActiveThemes();
    _isLoading = _themeManager.isLoading;
    _errorMessage = _themeManager.errorMessage;
    notifyListeners();
  }

  /// Public method to update themes from ThemeManager cache
  void updateFromCache() {
    _onThemesUpdated();
  }

  /// Loads themes using ThemeManager
  /// [forceRefresh] - If true, forces a fresh fetch from API
  Future<void> loadThemes({bool forceRefresh = false}) async {
    _setLoading(true);
    _errorMessage = null;
    notifyListeners();

    try {
      // Fetch themes from ThemeManager (will use cache if available)
      await _themeManager.fetchThemes(forceRefresh: forceRefresh);
      // Update local state from ThemeManager
      _onThemesUpdated();
    } on ApiException catch (e) {
      _errorMessage = e.message;
      // If ThemeManager has cached themes, use them
      if (_themeManager.hasThemes) {
        _onThemesUpdated();
      } else {
        // Fallback to mock themes only if API fails and no cache
        _themes = _getMockThemes();
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = 'Failed to load themes: $e';
      // If ThemeManager has cached themes, use them
      if (_themeManager.hasThemes) {
        _onThemesUpdated();
      } else {
        // Fallback to mock themes for development
        _themes = _getMockThemes();
        notifyListeners();
      }
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

  /// Updates session with selected theme (Step 4)
  /// Called when user taps "Continue" button after selecting a theme
  /// Makes PATCH /api/sessions/{sessionId} with only selectedThemeId
  Future<bool> updateSessionWithTheme() async {
    if (_selectedTheme == null) {
      _errorMessage = 'No theme selected. Please select a theme first.';
      notifyListeners();
      return false;
    }

    final sessionId = _sessionManager.sessionId;
    if (sessionId == null) {
      _errorMessage = 'No active session found. Please accept terms first.';
      notifyListeners();
      return false;
    }

    _isUpdatingSession = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Step 4: Update session with selected theme
      // PATCH /api/sessions/{sessionId} with only selectedThemeId
      final response = await _apiService.updateSession(
        sessionId: sessionId,
        selectedThemeId: _selectedTheme!.id,
        // userImageUrl is not provided - photo already uploaded in Step 3
      );

      // Save the response to SessionManager
      // Response includes: id, selectedThemeId, selectedCategoryId
      _sessionManager.setSessionFromResponse(response);

      _isUpdatingSession = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _isUpdatingSession = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Failed to update session with theme: ${e.toString()}';
      _isUpdatingSession = false;
      notifyListeners();
      return false;
    }
  }
}

