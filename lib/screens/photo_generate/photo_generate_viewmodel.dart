import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../photo_capture/photo_model.dart';
import '../theme_selection/theme_model.dart';
import '../../utils/logger.dart';
import '../../services/error_reporting/error_reporting_manager.dart';

/// Model for a generated image
class GeneratedImage {
  final String id;
  final String imageUrl;
  final ThemeModel theme;
  final bool isSelected;

  GeneratedImage({
    required this.id,
    required this.imageUrl,
    required this.theme,
    this.isSelected = false,
  });

  GeneratedImage copyWith({
    String? id,
    String? imageUrl,
    ThemeModel? theme,
    bool? isSelected,
  }) {
    return GeneratedImage(
      id: id ?? this.id,
      imageUrl: imageUrl ?? this.imageUrl,
      theme: theme ?? this.theme,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}

class PhotoGenerateViewModel extends ChangeNotifier {
  final ApiService _apiService;
  final SessionManager _sessionManager;
  
  PhotoModel? _originalPhoto;
  ThemeModel? _selectedTheme;
  List<GeneratedImage> _generatedImages = [];
  bool _isGenerating = false;
  bool _isLoadingMore = false;
  String? _errorMessage;
  int _triesRemaining = 3; // Allow 3 tries total (initial + 2 more)
  int _currentAttempt = 1; // Track attempt number for API
  
  // Timer for generation progress
  Timer? _timer;
  int _elapsedSeconds = 0;
  
  // Generation progress message
  String _progressMessage = '';
  
  // Cancellation flag
  bool _isCancelled = false;

  PhotoGenerateViewModel({
    ApiService? apiService,
    SessionManager? sessionManager,
  })  : _apiService = apiService ?? ApiService(),
        _sessionManager = sessionManager ?? SessionManager();

  // Getters
  PhotoModel? get originalPhoto => _originalPhoto;
  ThemeModel? get selectedTheme => _selectedTheme;
  List<GeneratedImage> get generatedImages => _generatedImages;
  bool get isGenerating => _isGenerating;
  bool get isLoadingMore => _isLoadingMore;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;
  int get triesRemaining => _triesRemaining;
  bool get canTryDifferentStyle => _triesRemaining > 0 && !_isGenerating && !_isLoadingMore;
  int get elapsedSeconds => _elapsedSeconds;
  String get progressMessage => _progressMessage;
  bool get isCancelled => _isCancelled;
  
  // Check if any operation is in progress
  bool get isOperationInProgress => _isGenerating || _isLoadingMore;
  
  // Get all selected generated images (for proceeding to payment)
  List<GeneratedImage> get selectedGeneratedImages {
    return _generatedImages.where((img) => img.isSelected).toList();
  }
  
  // Check if at least one image is selected
  bool get hasSelectedImages => selectedGeneratedImages.isNotEmpty;
  
  // Get count of selected images
  int get selectedCount => _generatedImages.where((img) => img.isSelected).length;
  
  bool get hasGeneratedImages => _generatedImages.isNotEmpty;

  /// Initialize with photo and theme
  void initialize(PhotoModel photo, ThemeModel theme) {
    _originalPhoto = photo;
    _selectedTheme = theme;
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

  void _updateProgress(String message) {
    _progressMessage = message;
    notifyListeners();
  }

  /// Generate image with the current theme
  Future<bool> generateImage() async {
    if (_selectedTheme == null || _originalPhoto == null) {
      _errorMessage = 'No theme or photo selected';
      notifyListeners();
      return false;
    }

    _resetCancellation();
    _isGenerating = true;
    _errorMessage = null;
    _progressMessage = 'Preparing transformation...';
    notifyListeners();
    
    _startTimer();

    try {
      AppLogger.debug('🎨 Starting image generation with theme: ${_selectedTheme!.name}');
      ErrorReportingManager.log('Starting image generation');
      
      _updateProgress('Transforming your look...');
      
      // Call the API to generate the image (120s timeout so UI cannot hang)
      const generateTimeout = Duration(seconds: 120);
      final result = await _apiService.generateImage(
        sessionId: _sessionManager.sessionId!,
        attempt: _currentAttempt,
        originalPhotoId: _originalPhoto!.id,
        themeId: _selectedTheme!.id,
        onProgress: (message) {
          _updateProgress(message);
        },
      ).timeout(
        generateTimeout,
        onTimeout: () => throw TimeoutException(
          'Generation timed out after ${generateTimeout.inSeconds} seconds',
        ),
      );

      _stopTimer();

      if (result.imageUrl.isNotEmpty) {
        // Add to generated images list
        final generatedImage = GeneratedImage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          imageUrl: result.imageUrl,
          theme: _selectedTheme!,
          isSelected: _generatedImages.isEmpty, // Select first one by default
        );
        
        _generatedImages.add(generatedImage);
        _triesRemaining--;
        _currentAttempt++;
        
        AppLogger.debug('✅ Image generated successfully');
        ErrorReportingManager.log('Image generated successfully');
        
        return true;
      } else {
        _errorMessage = 'Failed to generate image';
        return false;
      }
    } on TimeoutException {
      _errorMessage = 'Generation took too long. Please try again.';
      return false;
    } catch (e, stackTrace) {
      _stopTimer();
      AppLogger.error('❌ Error generating image: $e');
      await ErrorReportingManager.recordError(
        e,
        stackTrace,
        reason: 'Image generation failed',
      );
      
      _errorMessage = 'Generation failed: ${e.toString()}';
      return false;
    } finally {
      _stopTimer();
      _isGenerating = false;
      _progressMessage = '';
      notifyListeners();
    }
  }

  /// Try a different style (regenerate with same or different theme)
  Future<bool> tryDifferentStyle(ThemeModel newTheme) async {
    if (!canTryDifferentStyle || _originalPhoto == null) {
      return false;
    }

    _resetCancellation();
    _isLoadingMore = true;
    _errorMessage = null;
    _progressMessage = 'Trying new style...';
    notifyListeners();
    
    _startTimer();

    try {
      // Update session with new theme
      _selectedTheme = newTheme;
      
      AppLogger.debug('🎨 Trying different style with theme: ${newTheme.name}');
      
      // Update session with the new theme (30s timeout)
      const updateTimeout = Duration(seconds: 30);
      try {
        await _apiService.updateSession(
          sessionId: _sessionManager.sessionId!,
          selectedThemeId: newTheme.id,
        ).timeout(
          updateTimeout,
          onTimeout: () => throw TimeoutException(
            'Update theme timed out after ${updateTimeout.inSeconds} seconds',
          ),
        );
      } on TimeoutException {
        _errorMessage = 'Request took too long. Please try again.';
        return false;
      } catch (e) {
        _errorMessage = 'Failed to update theme: $e';
        return false;
      }
      
      _updateProgress('Transforming your look...');
      
      // Generate new image (120s timeout)
      const generateTimeout = Duration(seconds: 120);
      final result = await _apiService.generateImage(
        sessionId: _sessionManager.sessionId!,
        attempt: 1, // Always use 1 for new theme
        originalPhotoId: _originalPhoto!.id,
        themeId: newTheme.id,
        onProgress: (message) {
          _updateProgress(message);
        },
      ).timeout(
        generateTimeout,
        onTimeout: () => throw TimeoutException(
          'Generation timed out after ${generateTimeout.inSeconds} seconds',
        ),
      );

      _stopTimer();

      if (result.imageUrl.isNotEmpty) {
        final generatedImage = GeneratedImage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          imageUrl: result.imageUrl,
          theme: newTheme,
          isSelected: true, // Auto-select new theme images
        );
        
        _generatedImages.add(generatedImage);
        _triesRemaining--;
        // Don't increment _currentAttempt here since we use attempt=1 for each new theme
        
        return true;
      } else {
        _errorMessage = 'Failed to generate image';
        return false;
      }
    } on TimeoutException {
      _errorMessage = 'Generation took too long. Please try again.';
      return false;
    } catch (e, stackTrace) {
      _stopTimer();
      AppLogger.error('❌ Error trying different style: $e');
      await ErrorReportingManager.recordError(
        e,
        stackTrace,
        reason: 'Try different style failed',
      );
      
      // Extract cleaner error message for user
      String errorMsg = e.toString();
      if (errorMsg.contains('Status 500')) {
        errorMsg = 'Server error. Please try again or start over.';
      }
      _errorMessage = errorMsg;
      return false;
    } finally {
      _stopTimer();
      _isLoadingMore = false;
      _progressMessage = '';
      notifyListeners();
    }
  }

  /// Toggle selection of a generated image (multi-select)
  /// Ensures at least one image is always selected
  void toggleImageSelection(String imageId) {
    // Find the image being toggled
    final targetImage = _generatedImages.firstWhere(
      (img) => img.id == imageId,
      orElse: () => _generatedImages.first,
    );
    
    // If trying to deselect and it's the only selected one, don't allow
    if (targetImage.isSelected) {
      final currentSelectedCount = _generatedImages.where((img) => img.isSelected).length;
      if (currentSelectedCount <= 1) {
        // Can't deselect the last selected image - at least one must be selected
        return;
      }
    }
    
    _generatedImages = _generatedImages.map((img) {
      if (img.id == imageId) {
        return img.copyWith(isSelected: !img.isSelected);
      }
      return img;
    }).toList();
    notifyListeners();
  }
  
  /// Select all images
  void selectAllImages() {
    _generatedImages = _generatedImages.map((img) {
      return img.copyWith(isSelected: true);
    }).toList();
    notifyListeners();
  }
  
  /// Deselect all images
  void deselectAllImages() {
    _generatedImages = _generatedImages.map((img) {
      return img.copyWith(isSelected: false);
    }).toList();
    notifyListeners();
  }

  /// Clear error
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Cancel the current operation
  /// This sets a flag that the operation methods check
  void cancelOperation() {
    _isCancelled = true;
    _stopTimer();
    _isGenerating = false;
    _isLoadingMore = false;
    _progressMessage = '';
    _errorMessage = 'Operation cancelled';
    notifyListeners();
    AppLogger.debug('🚫 Operation cancelled by user');
  }
  
  /// Reset cancellation flag (call before starting new operation)
  void _resetCancellation() {
    _isCancelled = false;
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }
}
