import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme_model.dart';
import '../../services/theme_manager.dart';
import '../../utils/constants.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../services/error_reporting/error_reporting_manager.dart';
import '../../utils/exceptions.dart';

class ThemeViewModel extends ChangeNotifier {
  final ThemeManager _themeManager;
  final ApiService _apiService;
  final SessionManager _sessionManager;
  List<ThemeModel> _themes = [];
  ThemeModel? _selectedTheme;
  ThemeModel? _armedTheme;
  bool _isLoading = false;
  bool _isUpdatingSession = false;
  String? _errorMessage;
  bool _showNoThemesMessage = false;
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
  ThemeModel? get armedTheme => _armedTheme;
  bool get hasArmedTheme => _armedTheme != null;
  bool get isLoading => _isLoading;
  bool get isUpdatingSession => _isUpdatingSession;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;
  /// True when API returned successfully but no themes are available (report and show snackbar once).
  bool get showNoThemesMessage => _showNoThemesMessage;

  /// Category tab ids: "All" plus unique categoryIds from themes.
  List<String> get categoryIds {
    if (_themes.isEmpty) return ['All'];
    final ids = _themes.map((t) => t.categoryId).toSet().toList()..sort();
    return ['All', ...ids];
  }

  /// Known categoryId -> display name when API does not send categoryName.
  static const Map<String, String> _categoryIdToName = {
    'all': 'All',
    'royal': 'Royal',
    'superhero': 'Superhero',
    'wedding': 'Wedding',
    'fantasy': 'Fantasy',
    'cat-1': 'General',
    'vintage': 'Vintage',
    'portrait': 'Portrait',
  };

  /// Display name for category (for tabs). Uses API categoryName when present, else known mapping, else title-case of id.
  String getCategoryDisplayName(String id) {
    if (id == 'All') return 'All';
    for (final t in _themes) {
      if (t.categoryId == id && t.categoryName != null && t.categoryName!.isNotEmpty) {
        return t.categoryName!;
      }
    }
    final key = id.toLowerCase();
    if (_categoryIdToName.containsKey(key)) {
      return _categoryIdToName[key]!;
    }
    final parts = id.split(RegExp(r'[-_\s]+'));
    return parts
        .map((p) => p.isEmpty
            ? p
            : '${p[0].toUpperCase()}${p.length > 1 ? p.substring(1).toLowerCase() : ''}')
        .join(' ');
  }

  /// Currently selected category ("All" or a categoryId).
  String get selectedCategoryId => _selectedCategoryId;
  String _selectedCategoryId = 'All';

  /// Themes filtered by selected category.
  List<ThemeModel> get filteredThemes {
    if (_selectedCategoryId == 'All') return _themes;
    return _themes.where((t) => t.categoryId == _selectedCategoryId).toList();
  }

  /// Current carousel center index (for filtered themes).
  int get carouselIndex => _carouselIndex;
  int _carouselIndex = 0;

  /// When true, Select Theme shows a scrollable card grid; when false, the 3D carousel + thumbnails.
  bool get useCardGridLayout => _useCardGridLayout;
  bool _useCardGridLayout = false;

  /// Loads [useCardGridLayout] from local storage (web + mobile).
  Future<void> loadLayoutPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(AppConstants.kPrefsThemeSelectionCardLayout);
    if (v != null && v != _useCardGridLayout) {
      _useCardGridLayout = v;
      notifyListeners();
    }
  }

  Future<void> setUseCardGridLayout(bool value) async {
    if (_useCardGridLayout == value) return;
    _useCardGridLayout = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.kPrefsThemeSelectionCardLayout, value);
  }

  void selectCategory(String id) {
    _selectedCategoryId = id;
    _carouselIndex = 0;
    final list = filteredThemes;
    _selectedTheme = list.isEmpty ? null : list[0];
    _armedTheme = null;
    notifyListeners();
  }

  void setCarouselIndex(int index) {
    final list = filteredThemes;
    if (index < 0 || index >= list.length) return;
    _carouselIndex = index;
    _selectedTheme = list[index];
    notifyListeners();
  }

  /// Advance carousel by one (for auto-play). Call from view timer.
  void advanceCarousel() {
    final list = filteredThemes;
    if (list.isEmpty) return;
    final next = (_carouselIndex + 1) % list.length;
    setCarouselIndex(next);
  }

  /// Called when ThemeManager updates themes
  /// Made public so view can call it to use cached themes immediately
  void _onThemesUpdated() {
    _themes = _themeManager.getActiveThemes();
    _isLoading = _themeManager.isLoading;
    _errorMessage = _themeManager.errorMessage;
    final list = filteredThemes;
    if (list.isNotEmpty && _carouselIndex >= list.length) {
      _carouselIndex = 0;
      _selectedTheme = list[0];
    } else if (list.isNotEmpty && _selectedTheme == null) {
      _selectedTheme = list[0];
    }
    if (_armedTheme != null && !_themes.any((t) => t.id == _armedTheme!.id)) {
      _armedTheme = null;
    }
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
      if (_themes.isEmpty) {
        await ErrorReportingManager.recordError(
          Exception('Themes API returned no themes'),
          null,
          reason: 'No themes available',
          extraInfo: {'source': 'theme_selection_load'},
        );
        _showNoThemesMessage = true;
      }
    } on ApiException catch (e) {
      _errorMessage = e.message;
      // If ThemeManager has cached themes, use them
      if (_themeManager.hasThemes) {
        _onThemesUpdated();
      } else {
        _themes = [];
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = 'Failed to load themes: $e';
      // If ThemeManager has cached themes, use them
      if (_themeManager.hasThemes) {
        _onThemesUpdated();
      } else {
        _themes = [];
        notifyListeners();
      }
    } finally {
      _setLoading(false);
    }
  }

  /// Selects a theme
  void selectTheme(ThemeModel theme) {
    _selectedTheme = theme;
    _errorMessage = null;
    notifyListeners();
  }

  /// Explicitly confirms a theme. This remains stable even if [selectedTheme] changes due to carousel auto-scroll.
  void armTheme(ThemeModel theme) {
    _armedTheme = theme;
    _errorMessage = null;
    notifyListeners();
  }

  void clearArmedTheme() {
    if (_armedTheme == null) return;
    _armedTheme = null;
    notifyListeners();
  }

  /// Clears the selected theme
  void clearSelection() {
    _selectedTheme = null;
    _armedTheme = null;
    notifyListeners();
  }

  /// Call after showing the "no themes available" snackbar so it is not shown again.
  void clearNoThemesMessage() {
    if (_showNoThemesMessage) {
      _showNoThemesMessage = false;
      notifyListeners();
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  /// Updates session with selected theme (Step 4)
  /// Called when user taps "Continue" button after selecting a theme
  /// Makes PATCH /api/sessions/{sessionId} with only selectedThemeId
  Future<bool> updateSessionWithTheme() async {
    final theme = _armedTheme ?? _selectedTheme;
    if (theme == null) {
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
      // Use a 30s timeout so the UI cannot hang indefinitely
      const updateTimeout = Duration(seconds: 30);
      final response = await _apiService.updateSession(
        sessionId: sessionId,
        selectedThemeId: theme.id,
        // userImageUrl is not provided - photo already uploaded in Step 3
      ).timeout(
        updateTimeout,
        onTimeout: () => throw TimeoutException(
          'Update session timed out after ${updateTimeout.inSeconds} seconds',
        ),
      );

      // Save the response to SessionManager
      // Response includes: id, selectedThemeId, selectedCategoryId
      _sessionManager.setSessionFromResponse(response);

      return true;
    } on TimeoutException {
      _errorMessage = 'Request took too long. Please check your connection and try again.';
      return false;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Failed to update session with theme: ${e.toString()}';
      return false;
    } finally {
      _isUpdatingSession = false;
      notifyListeners();
    }
  }
}

