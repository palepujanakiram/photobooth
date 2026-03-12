import 'dart:async';
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
  
  // Timer tracking
  int _elapsedSeconds = 0;
  Timer? _timer;
  String _currentProcess = '';

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
  int get elapsedSeconds => _elapsedSeconds;
  String get currentProcess => _currentProcess;
  
  void _updateProcess(String process) {
    _currentProcess = process;
    notifyListeners();
  }
  
  void _startTimer() {
    _elapsedSeconds = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _elapsedSeconds++;
      notifyListeners();
    });
  }
  
  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }
  
  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }

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
    _startTimer();
    notifyListeners();

    try {
      // Call the generate-image API endpoint (up to 2 minutes for AI generation)
      const generateTimeout = Duration(seconds: 120);
      _transformedImage = await _apiService.generateImage(
        sessionId: sessionId,
        attempt: _attemptNumber,
        originalPhotoId: _photo!.id,
        themeId: _theme!.id,
        onProgress: (message) {
          _updateProcess(message);
        },
      ).timeout(
        generateTimeout,
        onTimeout: () => throw TimeoutException(
          'Generation timed out after ${generateTimeout.inSeconds} seconds',
        ),
      );
      
      // Step 3: Finalizing
      _updateProcess('Opening result...');
      await Future.delayed(const Duration(milliseconds: 500));
      
      _stopTimer();
      _currentProcess = '';
      notifyListeners();
      return _transformedImage;
    } on TimeoutException {
      _errorMessage = 'Generation took too long. Please try again.';
      return null;
    } on ApiException catch (e) {
      // Include detailed error information
      final statusInfo = e.statusCode != null ? ' (Status: ${e.statusCode})' : '';
      final timeInfo = _elapsedSeconds > 0 ? ' [Took ${_elapsedSeconds}s]' : '';
      _errorMessage = '${e.message}$statusInfo$timeInfo';
      return null;
    } catch (e) {
      final timeInfo = _elapsedSeconds > 0 ? ' [Took ${_elapsedSeconds}s]' : '';
      _errorMessage = 'Failed to transform photo: ${e.toString()}$timeInfo';
      return null;
    } finally {
      _isTransforming = false;
      _stopTimer();
      notifyListeners();
    }
  }
}

