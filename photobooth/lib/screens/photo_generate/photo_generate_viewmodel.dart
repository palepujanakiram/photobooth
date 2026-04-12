import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../services/api_service.dart';
import '../../services/app_settings_manager.dart';
import '../../services/session_manager.dart';
import '../photo_capture/photo_model.dart';
import '../theme_selection/theme_model.dart';
import '../../utils/constants.dart';
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
  final AppSettingsManager? _appSettingsManager;

  PhotoModel? _originalPhoto;
  ThemeModel? _selectedTheme;
  List<GeneratedImage> _generatedImages = [];
  bool _isGenerating = false;
  bool _isLoadingMore = false;
  String? _errorMessage;
  int _maxRegenerationsAllowed = AppConstants.kDefaultMaxRegenerations;
  int _triesRemaining = AppConstants.kDefaultMaxRegenerations;
  
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
    AppSettingsManager? appSettingsManager,
  })  : _apiService = apiService ?? ApiService(),
        _sessionManager = sessionManager ?? SessionManager(),
        _appSettingsManager = appSettingsManager;

  // Getters
  PhotoModel? get originalPhoto => _originalPhoto;
  ThemeModel? get selectedTheme => _selectedTheme;
  List<GeneratedImage> get generatedImages => _generatedImages;
  bool get isGenerating => _isGenerating;
  bool get isLoadingMore => _isLoadingMore;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;
  int get triesRemaining => _triesRemaining;
  int get maxRegenerationsAllowed => _maxRegenerationsAllowed;
  bool get canTryDifferentStyle => _triesRemaining > 0 && !_isGenerating && !_isLoadingMore;
  /// Whether the UI may offer “add one more style” (cap from `/api/settings` `maxRegenerations`).
  bool get canShowAddAnotherStyleButton =>
      generatedImages.length < _maxRegenerationsAllowed && triesRemaining > 0;
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

  /// Newest generation is first in [_generatedImages] (prepended batches). It stays selected.
  String? get newestGeneratedImageId =>
      _generatedImages.isEmpty ? null : _generatedImages.first.id;

  bool isNewestGeneratedImage(String imageId) =>
      newestGeneratedImageId == imageId;

  void _ensureNewestAlwaysSelected() {
    if (_generatedImages.isEmpty) return;
    final id = _generatedImages.first.id;
    if (_generatedImages.first.isSelected) return;
    _generatedImages = _generatedImages
        .map((img) => img.id == id ? img.copyWith(isSelected: true) : img)
        .toList();
  }

  static String _newGeneratedImageId(int slotIndex) =>
      '${DateTime.now().microsecondsSinceEpoch}_$slotIndex';

  void _refreshMaxRegenerationsFromSettings() {
    final n = _appSettingsManager?.settings?.maxRegenerations;
    _maxRegenerationsAllowed = (n != null && n > 0)
        ? n
        : AppConstants.kDefaultMaxRegenerations;
  }

  /// Initialize with photo and theme
  void initialize(PhotoModel photo, ThemeModel theme) {
    _refreshMaxRegenerationsFromSettings();
    _originalPhoto = photo;
    _selectedTheme = theme;
    _triesRemaining = _maxRegenerationsAllowed;
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
      
      // Parallel SSE generation (GET /api/generate-stream-parallel); legacy POST
      // /api/generate-image remains on [ApiService.generateImage] if needed later.
      const generateTimeout = Duration(seconds: 120);
      final parallel = await _apiService
          .generateImageParallelStream(
        sessionId: _sessionManager.sessionId!,
        count: AppConstants.kAiParallelGenerationCount,
        originalPhotoId: _originalPhoto!.id,
        themeId: _selectedTheme!.id,
        onProgress: (message) {
          _updateProgress(message);
        },
      )
          .timeout(
        generateTimeout,
        onTimeout: () => throw TimeoutException(
          'Generation timed out after ${generateTimeout.inSeconds} seconds',
        ),
      );

      _stopTimer();

      if (parallel.firstImageUrl != null) {
        final newImages = <GeneratedImage>[];
        for (var i = 0; i < parallel.imageUrlsBySlot.length; i++) {
          final url = parallel.imageUrlsBySlot[i];
          if (url.isEmpty) continue;
          newImages.add(GeneratedImage(
            id: _newGeneratedImageId(i),
            imageUrl: url,
            theme: _selectedTheme!,
            isSelected: true,
          ));
        }
        // Newest generations first (stack order: latest left / first in list).
        _generatedImages = [...newImages, ..._generatedImages];
        _ensureNewestAlwaysSelected();
        _triesRemaining--;
        
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

  /// Call from the view before tryDifferentStyle so the UI shows loading immediately.
  void prepareToAddStyle(ThemeModel newTheme) {
    _isLoadingMore = true;
    _selectedTheme = newTheme;
    _errorMessage = null;
    _progressMessage = 'Adding your new style...';
    notifyListeners();
  }

  /// Try a different style (regenerate with same or different theme).
  /// May be called after prepareToAddStyle (then _isLoadingMore is already true).
  Future<bool> tryDifferentStyle(ThemeModel newTheme) async {
    if (_originalPhoto == null) return false;
    if (!_isLoadingMore && !canTryDifferentStyle) return false;

    _resetCancellation();
    _isLoadingMore = true;
    _errorMessage = null;
    _progressMessage = _progressMessage.isNotEmpty ? _progressMessage : 'Trying new style...';
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
      
      const generateTimeout = Duration(seconds: 120);
      final parallel = await _apiService
          .generateImageParallelStream(
        sessionId: _sessionManager.sessionId!,
        count: AppConstants.kAiParallelGenerationCount,
        originalPhotoId: _originalPhoto!.id,
        themeId: newTheme.id,
        onProgress: (message) {
          _updateProgress(message);
        },
      )
          .timeout(
        generateTimeout,
        onTimeout: () => throw TimeoutException(
          'Generation timed out after ${generateTimeout.inSeconds} seconds',
        ),
      );

      _stopTimer();

      if (parallel.firstImageUrl != null) {
        final newImages = <GeneratedImage>[];
        for (var i = 0; i < parallel.imageUrlsBySlot.length; i++) {
          final url = parallel.imageUrlsBySlot[i];
          if (url.isEmpty) continue;
          newImages.add(GeneratedImage(
            id: _newGeneratedImageId(i),
            imageUrl: url,
            theme: newTheme,
            isSelected: true,
          ));
        }
        _generatedImages = [...newImages, ..._generatedImages];
        _ensureNewestAlwaysSelected();
        _triesRemaining--;
        
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

  /// Toggle selection of a generated image (multi-select).
  /// At least one image must remain selected.
  void toggleImageSelection(String imageId) {
    final idx = _generatedImages.indexWhere((img) => img.id == imageId);
    if (idx < 0) return;
    final targetImage = _generatedImages[idx];

    if (targetImage.isSelected) {
      final currentSelectedCount =
          _generatedImages.where((img) => img.isSelected).length;
      if (currentSelectedCount <= 1) return;
    }

    _generatedImages = _generatedImages.map((img) {
      if (img.id == imageId) {
        return img.copyWith(isSelected: !img.isSelected);
      }
      return img;
    }).toList();
    notifyListeners();
  }

  int get initialPrintPrice =>
      _appSettingsManager?.settings?.initialPrice ??
      AppConstants.kDefaultInitialPrintPrice;

  int get additionalPrintPrice =>
      _appSettingsManager?.settings?.additionalPrintPrice ??
      AppConstants.kDefaultAdditionalPrintPrice;

  /// Total price based on how many generated images are selected.
  int get selectedTotalPrice {
    final count = selectedCount;
    if (count <= 0) return 0;
    return initialPrintPrice + (count > 1 ? (count - 1) * additionalPrintPrice : 0);
  }

  /// Remove a generated image by id. No-op if only one remains (keep at least one).
  /// Restores one "try" so the user can add a style again (e.g. re-add the removed theme).
  void removeGeneratedImage(String imageId) {
    if (_generatedImages.length <= 1) return;
    _generatedImages = _generatedImages.where((img) => img.id != imageId).toList();
    if (_generatedImages.isNotEmpty) {
      final newestId = _generatedImages.first.id;
      _generatedImages = _generatedImages
          .map((img) =>
              img.id == newestId ? img.copyWith(isSelected: true) : img)
          .toList();
    }
    // Give back one try so user can add a style again (including re-adding the removed one)
    if (_triesRemaining < _maxRegenerationsAllowed) _triesRemaining++;
    notifyListeners();
  }
  
  /// Select all images
  void selectAllImages() {
    _generatedImages = _generatedImages.map((img) {
      return img.copyWith(isSelected: true);
    }).toList();
    notifyListeners();
  }
  
  /// Deselect all except the newest (keeps at least one selected).
  void deselectAllImages() {
    if (_generatedImages.isEmpty) return;
    final newestId = _generatedImages.first.id;
    _generatedImages = _generatedImages.map((img) {
      return img.copyWith(isSelected: img.id == newestId);
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
