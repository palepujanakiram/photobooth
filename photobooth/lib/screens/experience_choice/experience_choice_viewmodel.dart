import 'package:flutter/foundation.dart';

import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../services/theme_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../utils/exceptions.dart';
import '../../utils/kiosk_offline_ux.dart';
import '../theme_selection/theme_model.dart';

/// Loads kiosk themes and starts the FotoFlashback session theme when chosen.
class ExperienceChoiceViewModel extends ChangeNotifier {
  ExperienceChoiceViewModel({
    ThemeManager? themeManager,
    ApiService? apiService,
    SessionManager? sessionManager,
  })  : _themeManager = themeManager ?? ThemeManager(),
        _api = apiService ?? ApiService(),
        _sessionManager = sessionManager ?? SessionManager();

  final ThemeManager _themeManager;
  final ApiService _api;
  final SessionManager _sessionManager;

  bool _loading = false;
  bool _startingFlashback = false;
  String? _errorMessage;
  List<ThemeModel> _themes = const [];

  bool get isLoading => _loading;
  bool get isStartingFlashback => _startingFlashback;
  String? get errorMessage => _errorMessage;
  bool get fotoFlashAvailable => _themes.any((t) => t.isPhotoStrip);

  /// Local / WAN-down sessions cannot run Fly Gemini AI.
  bool get isOffline => _sessionManager.isOfflineSession;

  /// FotoZen AI path — disabled offline so guests are not sent into network errors.
  bool get aiAvailable => !KioskOfflineUx.shouldDisableAiExperience(
        sessionOffline: isOffline,
      );

  ThemeModel? get fotoFlashTheme {
    for (final t in _themes) {
      if (t.isPhotoStrip) return t;
    }
    return null;
  }

  Future<void> load() async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _themes = await _themeManager.fetchThemes();
    } on ApiException catch (e) {
      _errorMessage = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Binds the seeded FotoFlashback theme to the session, then caller navigates.
  ///
  /// Offline / local sessions have no Fly row or kiosk token — bind [selectedThemeId]
  /// on-device instead of PATCH (avoids "Network error occurred" on Classic Start).
  Future<ThemeModel?> prepareFotoFlashback() async {
    final theme = fotoFlashTheme;
    if (theme == null) {
      _errorMessage = AppStrings.experienceFotoFlashUnavailable;
      notifyListeners();
      return null;
    }
    final sessionId = _sessionManager.sessionId?.trim() ?? '';
    if (sessionId.isEmpty) {
      _errorMessage = AppStrings.sessionPhotoSyncNoSession;
      notifyListeners();
      return null;
    }

    _startingFlashback = true;
    _errorMessage = null;
    notifyListeners();
    try {
      if (_sessionManager.isOfflineSession) {
        _bindClassicThemeLocally(theme);
        return theme;
      }
      final response = await _api.updateSession(
        sessionId: sessionId,
        selectedThemeId: theme.id,
      );
      _sessionManager.setSessionFromResponse(response);
      return theme;
    } on ApiException catch (e) {
      if (_isTransportFailureForClassicStart(e)) {
        _sessionManager.markSessionOffline();
        _bindClassicThemeLocally(theme);
        return theme;
      }
      _errorMessage = e.message;
      return null;
    } catch (_) {
      _errorMessage = AppStrings.experienceFotoFlashStartFailed;
      return null;
    } finally {
      _startingFlashback = false;
      notifyListeners();
    }
  }

  /// Connection / 5xx only — not auth or validation 4xx (those must surface).
  bool _isTransportFailureForClassicStart(ApiException e) {
    if (e.message == AppConstants.kErrorNetwork) return true;
    final code = e.statusCode;
    return code != null && code >= 500;
  }

  void _bindClassicThemeLocally(ThemeModel theme) {
    final session = _sessionManager.currentSession;
    if (session == null) return;
    final payload = session.toJson()..['selectedThemeId'] = theme.id;
    _sessionManager.setSessionFromResponse(payload);
  }
}
