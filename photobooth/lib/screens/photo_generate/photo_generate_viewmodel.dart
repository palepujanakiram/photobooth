import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../../services/api_service.dart';
import '../../services/app_settings_manager.dart';
import '../../services/session_manager.dart';
import '../photo_capture/photo_model.dart';
import '../theme_selection/theme_model.dart';
import '../../utils/constants.dart';
import '../../utils/exceptions.dart';
import '../../utils/logger.dart';
import '../../utils/secure_image_url.dart';
import '../../utils/transformation_step_display.dart';
import '../../services/generation_display_preferences.dart';
import '../../services/error_reporting/error_reporting_manager.dart';

/// One pipeline stage row for the progressive (filmstrip) generate layout.
class ProgressivePipelineStage {
  const ProgressivePipelineStage({
    required this.stepKey,
    this.active = false,
    this.complete = false,
    this.skipped = false,
    this.durationMs,
    this.previewImageUrl,
  });

  final String stepKey;
  final bool active;
  final bool complete;
  final bool skipped;
  final int? durationMs;
  final String? previewImageUrl;
}

/// In-flight slot while SSE parallel generation is streaming.
class LiveGenerationSlotState {
  final int index;
  final bool loading;
  final bool failed;
  final String? imageUrl;
  final double? qualityScore;

  const LiveGenerationSlotState({
    required this.index,
    this.loading = true,
    this.failed = false,
    this.imageUrl,
    this.qualityScore,
  });
}

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

  // Live SSE generation UI (parallel stream)
  double _liveProgress = 0;
  String? _liveCurrentStep;
  final Map<String, int> _liveStepDurationsMs = {};
  int? _liveAttempt;
  int? _liveTotalAttempts;
  double? _liveLastScore;
  String? _liveCommentary;
  List<LiveGenerationSlotState> _liveSlots = [];
  String? _lastTransformationRunId;

  bool _useProgressiveGenerationUi = false;
  bool _progressivePrefLoaded = false;
  List<ProgressivePipelineStage> _progressivePipelineStages = [];

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

  double get liveProgress => _liveProgress;
  String? get liveCurrentStep => _liveCurrentStep;
  Map<String, int> get liveStepDurationsMs =>
      Map<String, int>.unmodifiable(_liveStepDurationsMs);
  int? get liveAttempt => _liveAttempt;
  int? get liveTotalAttempts => _liveTotalAttempts;
  double? get liveLastScore => _liveLastScore;
  String? get liveCommentary => _liveCommentary;
  List<LiveGenerationSlotState> get liveSlots =>
      List<LiveGenerationSlotState>.unmodifiable(_liveSlots);
  int get liveSlotCount => _liveSlots.length;
  String? get lastTransformationRunId => _lastTransformationRunId;

  bool get useProgressiveGenerationUi => _useProgressiveGenerationUi;

  /// Progressive filmstrip + stage thumbs: only when pref is on **and** SSE runs (parallel > 1).
  bool get useProgressiveGenerationLayoutForSession =>
      _useProgressiveGenerationUi && _parallelSlotCount > 1;

  int get parallelImageSlotCount => _parallelSlotCount;

  List<ProgressivePipelineStage> get progressivePipelineStages =>
      List<ProgressivePipelineStage>.unmodifiable(_progressivePipelineStages);

  /// One line under the filmstrip: commentary, active step, or progress message.
  String? get progressiveOneLiner {
    final commentaryAllowed =
        _appSettingsManager?.settings?.showGenerationCommentary == true;
    if (commentaryAllowed &&
        _liveCommentary != null &&
        _liveCommentary!.trim().isNotEmpty) {
      return _liveCommentary!.trim();
    }
    final step = _liveCurrentStep;
    if (step != null && step.isNotEmpty) {
      return 'Working on: ${transformationStepDisplayLabel(step)}';
    }
    final m = _progressMessage.trim();
    return m.isNotEmpty ? m : null;
  }

  Future<void> loadProgressiveDisplayPreference() async {
    if (_progressivePrefLoaded) return;
    final v = await GenerationDisplayPreferences.getUseProgressiveGenerationUi();
    _useProgressiveGenerationUi = v;
    _progressivePrefLoaded = true;
    notifyListeners();
  }

  Future<void> setProgressiveGenerationUi(bool value) async {
    _useProgressiveGenerationUi = value;
    await GenerationDisplayPreferences.setUseProgressiveGenerationUi(value);
    notifyListeners();
  }

  Future<void> toggleProgressiveGenerationUi() async {
    await setProgressiveGenerationUi(!_useProgressiveGenerationUi);
  }
  
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

  /// 1-based attempt for POST `/api/generate-image` when `parallelImageCount` is 1.
  int get _nextGenerateAttempt =>
      _maxRegenerationsAllowed - _triesRemaining + 1;

  int get _parallelSlotCount =>
      _appSettingsManager?.resolveParallelImageCount() ??
      AppConstants.kAiParallelGenerationCount;

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

  void _resetLiveGenerationState() {
    _liveProgress = 0;
    _liveCurrentStep = null;
    _liveStepDurationsMs.clear();
    _liveAttempt = null;
    _liveTotalAttempts = null;
    _liveLastScore = null;
    _liveCommentary = null;
    _liveSlots = [];
    _lastTransformationRunId = null;
    _progressivePipelineStages = [];
  }

  void _clearLiveGenerationUi() {
    _liveProgress = 0;
    _liveCurrentStep = null;
    _liveStepDurationsMs.clear();
    _liveAttempt = null;
    _liveTotalAttempts = null;
    _liveLastScore = null;
    _liveCommentary = null;
    _liveSlots = [];
    _progressivePipelineStages = [];
  }

  String? _extractStepPreviewUrl(Map<String, dynamic> data) {
    for (final key in ['thumbnailUrl', 'previewUrl', 'imageUrl']) {
      final v = data[key];
      if (v is String && v.trim().isNotEmpty) {
        return SecureImageUrl.absolutize(v.trim());
      }
    }
    final od = data['outputData'];
    if (od is Map) {
      final m = Map<String, dynamic>.from(od);
      for (final key in ['thumbnailUrl', 'previewUrl', 'imageUrl', 'url']) {
        final v = m[key];
        if (v is String && v.trim().isNotEmpty) {
          return SecureImageUrl.absolutize(v.trim());
        }
      }
    }
    final id = data['inputData'];
    if (id is Map) {
      final m = Map<String, dynamic>.from(id);
      for (final key in ['thumbnailUrl', 'previewUrl', 'imageUrl', 'url']) {
        final v = m[key];
        if (v is String && v.trim().isNotEmpty) {
          return SecureImageUrl.absolutize(v.trim());
        }
      }
    }
    return null;
  }

  void _upsertProgressiveStage(
    String step, {
    bool? active,
    bool? complete,
    bool? skipped,
    int? durationMs,
    String? previewUrl,
  }) {
    final i = _progressivePipelineStages.indexWhere((e) => e.stepKey == step);
    final prev = i >= 0 ? _progressivePipelineStages[i] : null;
    final next = ProgressivePipelineStage(
      stepKey: step,
      active: active ?? prev?.active ?? false,
      complete: complete ?? prev?.complete ?? false,
      skipped: skipped ?? prev?.skipped ?? false,
      durationMs: durationMs ?? prev?.durationMs,
      previewImageUrl: previewUrl ?? prev?.previewImageUrl,
    );
    if (i >= 0) {
      final list = List<ProgressivePipelineStage>.from(_progressivePipelineStages);
      list[i] = next;
      _progressivePipelineStages = list;
    } else {
      _progressivePipelineStages = [..._progressivePipelineStages, next];
    }
  }

  void _handleGenerationSseEvent(String event, Map<String, dynamic> data) {
    final commentaryAllowed =
        _appSettingsManager?.settings?.showGenerationCommentary == true;

    switch (event) {
      case 'status':
      case 'start':
        final count = (data['imageCount'] as num?)?.toInt() ??
            (data['total'] as num?)?.toInt() ??
            _parallelSlotCount;
        if (count > 0) {
          _liveSlots = List.generate(
            count,
            (i) => LiveGenerationSlotState(index: i, loading: true),
          );
        }
        _liveProgress = math.max(_liveProgress, 15.0);
        break;
      case 'step':
        final step = data['step'] as String?;
        final st = data['status'] as String?;
        final previewUrl = step != null ? _extractStepPreviewUrl(data) : null;
        if (step != null && st == 'active') {
          _liveCurrentStep = step;
          _upsertProgressiveStage(
            step,
            active: true,
            complete: false,
            previewUrl: previewUrl,
          );
        }
        if (step != null && st == 'complete') {
          final skipped = data['skipped'] == true;
          int? ms;
          final rawMs = data['durationMs'];
          if (rawMs is int) {
            ms = rawMs;
          } else if (rawMs is num) {
            ms = rawMs.toInt();
          }
          if (!skipped) {
            _liveStepDurationsMs[step] = ms ?? _liveStepDurationsMs[step] ?? 0;
          }
          _upsertProgressiveStage(
            step,
            active: false,
            complete: !skipped,
            skipped: skipped,
            durationMs: ms,
            previewUrl: previewUrl,
          );
          if (_liveCurrentStep == step) {
            _liveCurrentStep = null;
          }
        }
        break;
      case 'attempt_start':
        _liveAttempt = (data['attempt'] as num?)?.toInt();
        _liveTotalAttempts = (data['totalAttempts'] as num?)?.toInt();
        break;
      case 'attempt_complete':
        _liveLastScore = (data['score'] as num?)?.toDouble();
        break;
      case 'image_complete':
        int? idx;
        final rawIdx = data['index'];
        if (rawIdx is int) {
          idx = rawIdx;
        } else if (rawIdx is num) {
          idx = rawIdx.toInt();
        }
        final rawUrl = data['imageUrl'] as String?;
        final q = (data['qualityScore'] as num?)?.toDouble();
        if (idx != null &&
            idx >= 0 &&
            idx < _liveSlots.length &&
            rawUrl != null &&
            rawUrl.isNotEmpty) {
          final next = List<LiveGenerationSlotState>.from(_liveSlots);
          final url = SecureImageUrl.absolutize(rawUrl);
          next[idx] = LiveGenerationSlotState(
            index: idx,
            loading: false,
            failed: false,
            imageUrl: url,
            qualityScore: q,
          );
          _liveSlots = next;
        }
        final c = data['completed'];
        final t = data['total'];
        if (c is num && t is num && t > 0) {
          _liveProgress = math.min(92, 15 + (c / t) * 77);
        }
        break;
      case 'image_failed':
        int? idx;
        final rawIdx = data['index'];
        if (rawIdx is int) {
          idx = rawIdx;
        } else if (rawIdx is num) {
          idx = rawIdx.toInt();
        }
        if (idx != null && idx >= 0 && idx < _liveSlots.length) {
          final prev = _liveSlots[idx];
          final next = List<LiveGenerationSlotState>.from(_liveSlots);
          next[idx] = LiveGenerationSlotState(
            index: idx,
            loading: false,
            failed: true,
            imageUrl: prev.imageUrl,
            qualityScore: prev.qualityScore,
          );
          _liveSlots = next;
        }
        break;
      case 'commentary':
        if (commentaryAllowed) {
          _liveCommentary = data['message'] as String?;
        }
        break;
      case 'commentary_clear':
        _liveCommentary = null;
        break;
      case 'complete':
        _liveProgress = 100;
        break;
      default:
        break;
    }
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
    _resetLiveGenerationState();
    _isGenerating = true;
    _errorMessage = null;
    _progressMessage = 'Preparing transformation...';
    notifyListeners();
    
    _startTimer();

    try {
      try {
        await _appSettingsManager?.fetchSettings();
      } catch (_) {
        // Use [resolveParallelImageCount] fallback if settings unavailable.
      }
      AppLogger.debug('🎨 Starting image generation with theme: ${_selectedTheme!.name}');
      ErrorReportingManager.log('Starting image generation');
      
      _updateProgress('Transforming your look...');

      const generateTimeout = Duration(seconds: 120);
      final parallel = await _apiService
          .generateImages(
        sessionId: _sessionManager.sessionId!,
        count: _parallelSlotCount,
        attempt: _nextGenerateAttempt,
        originalPhotoId: _originalPhoto!.id,
        themeId: _selectedTheme!.id,
        onProgress: (message) {
          _updateProgress(message);
        },
        onSseEvent: _parallelSlotCount > 1 ? _handleGenerationSseEvent : null,
      )
          .timeout(
        generateTimeout,
        onTimeout: () => throw TimeoutException(
          'Generation timed out after ${generateTimeout.inSeconds} seconds',
        ),
      );

      _stopTimer();

      if (parallel.firstImageUrl != null) {
        _lastTransformationRunId = parallel.runId;
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
      
      _errorMessage = e is ApiException
          ? 'Generation failed: ${e.userFacingMessage}'
          : 'Generation failed: ${e.toString()}';
      return false;
    } finally {
      _stopTimer();
      _isGenerating = false;
      _progressMessage = '';
      _clearLiveGenerationUi();
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
    _resetLiveGenerationState();
    _isLoadingMore = true;
    _errorMessage = null;
    _progressMessage = _progressMessage.isNotEmpty ? _progressMessage : 'Trying new style...';
    notifyListeners();
    
    _startTimer();

    try {
      try {
        await _appSettingsManager?.fetchSettings();
      } catch (_) {}
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
          .generateImages(
        sessionId: _sessionManager.sessionId!,
        count: _parallelSlotCount,
        attempt: _nextGenerateAttempt,
        originalPhotoId: _originalPhoto!.id,
        themeId: newTheme.id,
        onProgress: (message) {
          _updateProgress(message);
        },
        onSseEvent: _parallelSlotCount > 1 ? _handleGenerationSseEvent : null,
      )
          .timeout(
        generateTimeout,
        onTimeout: () => throw TimeoutException(
          'Generation timed out after ${generateTimeout.inSeconds} seconds',
        ),
      );

      _stopTimer();

      if (parallel.firstImageUrl != null) {
        _lastTransformationRunId = parallel.runId;
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
      
      _errorMessage = e is ApiException
          ? e.userFacingMessage
          : (e.toString().contains('Status 500')
              ? 'Server error. Please try again or start over.'
              : e.toString());
      return false;
    } finally {
      _stopTimer();
      _isLoadingMore = false;
      _progressMessage = '';
      _clearLiveGenerationUi();
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
    _clearLiveGenerationUi();
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
