import 'package:flutter/foundation.dart';
import '../photo_capture/photo_model.dart';
import '../theme_selection/theme_model.dart';
import '../result/transformed_image_model.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../utils/exceptions.dart';

class ReviewViewModel extends ChangeNotifier {
  final ApiService _apiService;
  final SessionManager _sessionManager;
  final PhotoModel? _photo;
  final ThemeModel? _theme;
  TransformedImageModel? _transformedImage;
  bool _isTransforming = false;
  String? _errorMessage;
  final int _attemptNumber = 1;

  ReviewViewModel({
    required PhotoModel photo,
    required ThemeModel theme,
    ApiService? apiService,
    SessionManager? sessionManager,
  })  : _photo = photo,
        _theme = theme,
        _apiService = apiService ?? ApiService(),
        _sessionManager = sessionManager ?? SessionManager();

  PhotoModel? get photo => _photo;
  ThemeModel? get theme => _theme;
  TransformedImageModel? get transformedImage => _transformedImage;
  bool get isTransforming => _isTransforming;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;

  /// Transforms the photo using AI generation
  /// Makes API call to POST /api/generate-image with sessionId and attempt number
  /// Handles timeout (60s) and retries once before showing error
  Future<TransformedImageModel?> transformPhoto() async {
    if (_photo == null || _theme == null) {
      _errorMessage = 'Photo or theme not set';
      notifyListeners();
      return null;
    }

    // Get sessionId from SessionManager
    final sessionId = _sessionManager.sessionId;
    if (sessionId == null) {
      _errorMessage = 'No active session found. Please accept terms first.';
      notifyListeners();
      return null;
    }

    _isTransforming = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Call the new generate-image API endpoint
      _transformedImage = await _apiService.generateImage(
        sessionId: sessionId,
        attempt: _attemptNumber,
        originalPhotoId: _photo!.id,
        themeId: _theme!.id,
      );
      
      notifyListeners();
      return _transformedImage;
    } on ApiException catch (e) {
      // Include status code in error message if available
      if (e.statusCode != null) {
        _errorMessage = '${e.message} (Status: ${e.statusCode})';
      } else {
        _errorMessage = e.message;
      }
      notifyListeners();
      return null;
    } catch (e) {
      _errorMessage = 'Failed to transform photo: ${e.toString()}';
      notifyListeners();
      return null;
    } finally {
      _isTransforming = false;
      notifyListeners();
    }
  }
}

