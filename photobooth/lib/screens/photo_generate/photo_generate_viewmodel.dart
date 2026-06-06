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
import '../../models/parallel_generation_result.dart';
import '../../services/error_reporting/error_reporting_manager.dart';

part 'photo_generate_viewmodel_helpers.dart';

/// Best-effort: session JSON may expose an in-flight generation run id (server-dependent).
/// Normalizes API `step.stage` to keys in [kPipelineFunnelRecognizedStageKeys].
String canonicalPipelineStageKey(String raw) {
  final s = raw.trim().toLowerCase();
  switch (s) {
    case 'preprocess':
      return 'preprocessing';
    case 'ai':
      return 'ai_generation';
    default:
      return s;
  }
}

/// Core API stages always shown (pending until `steps[]` includes them).
const List<String> kPipelineFunnelCoreStages = [
  'preprocessing',
  'background_removal',
  'ai_generation',
  'scene_lighting',
  'face_relight',
  'frame_composite',
];

/// Metadata-only stages: only add a stamp if the step exists in `steps[]` (no reserved slot).
const List<String> kPipelineFunnelOptionalMetadataStages = [
  'exif_stamp',
  'c2pa_sign',
];

const String kPipelineFunnelStorageStage = 'storage';

/// API `stage` keys the funnel strip understands (others ignored).
const Set<String> kPipelineFunnelRecognizedStageKeys = {
  ...kPipelineFunnelCoreStages,
  ...kPipelineFunnelOptionalMetadataStages,
  kPipelineFunnelStorageStage,
};

const Set<String> kPipelineFunnelMetadataOnlyStages = {
  'exif_stamp',
  'c2pa_sign',
};

/// Client-only leading slot: booth capture (shown before server `preprocessing`).
const String kPipelineDeviceCaptureStageKey = 'device_capture';

/// One slot in the pipeline strip (device capture + core + optional metadata + storage).
class PipelineFunnelSlot {
  const PipelineFunnelSlot({
    required this.stageKey,
    required this.label,
    this.displayPreviewUrl,
    required this.isPending,
    required this.isActive,
    required this.isFinished,
    this.isDeviceCapture = false,
    this.isMetadataOnlyStage = false,
  });

  final String stageKey;
  final String label;
  /// Deduped preview: null if no API image yet, or same pixels as the previous slot.
  final String? displayPreviewUrl;
  final bool isPending;
  final bool isActive;
  final bool isFinished;
  /// True for [kPipelineDeviceCaptureStageKey] — use [PhotoModel.imageFile] in the view.
  final bool isDeviceCapture;
  /// EXIF / C2PA: usually no [displayPreviewUrl]; show badge UI instead of expecting pixels.
  final bool isMetadataOnlyStage;
}

String? parseActiveTransformationRunIdFromSession(Map<String, dynamic>? m) {
  if (m == null) return null;
  for (final key in [
    'activeTransformationRunId',
    'active_transformation_run_id',
    'currentTransformationRunId',
    'transformationRunId',
    'pendingRunId',
    'generationRunId',
    'activeRunId',
  ]) {
    final v = m[key];
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  final ar = m['activeRun'];
  if (ar is Map) {
    final id = ar['id'];
    if (id is String && id.trim().isNotEmpty) return id.trim();
  }
  return null;
}

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

/// One step from `GET /api/generation-runs/:runId` for live progress thumbnails.
class GenerationRunStepPreview {
  const GenerationRunStepPreview({
    required this.stage,
    required this.status,
    this.previewUrl,
  });

  final String stage;
  final String status;
  final String? previewUrl;

  bool get isFinished {
    final s = status.toLowerCase();
    return s == 'complete' ||
        s == 'completed' ||
        s == 'success' ||
        s == 'succeeded' ||
        s == 'skipped' ||
        s == 'failed' ||
        s == 'error';
  }

  bool get isActive {
    final s = status.toLowerCase();
    return s == 'active' || s == 'running' || s == 'in_progress';
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

  bool _useProgressiveGenerationUi = true;
  bool _progressivePrefLoaded = false;
  List<ProgressivePipelineStage> _progressivePipelineStages = [];

  /// Stamp id under the app-bar subtitle (`source`, `stage:…`, `live:…`). Null = default hero.
  String? _selectedHeroStampId;

  /// Poll `GET /api/generation-runs/:id` (same payload as Transformation details) during generation.
  Timer? _generationRunPollTimer;
  String? _polledTransformationRunId;
  List<GenerationRunStepPreview> _generationRunStepPreviews = [];
  bool _generationRunPollInFlight = false;

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

  String? get selectedHeroStampId => _selectedHeroStampId;

  /// Fixed pipeline stamps under “Your AI-transformed portrait awaits” (in-frame capture + 7 API stages).
  /// Stays visible after generation until the user leaves (funnel state is preserved).
  bool get showProgressStampStrip {
    if (_originalPhoto == null) return false;
    if (_isGenerating || _isLoadingMore) return true;
    return hasGeneratedImages ||
        _generationRunStepPreviews.isNotEmpty ||
        (_lastTransformationRunId != null &&
            _lastTransformationRunId!.trim().isNotEmpty);
  }

  List<GenerationRunStepPreview> get generationRunStepPreviews =>
      List<GenerationRunStepPreview>.unmodifiable(_generationRunStepPreviews);

  /// Final output thumbnail to keep in the stamp strip after completion.
  String? get newestGeneratedImageUrl {
    if (_generatedImages.isEmpty) return null;
    return _generatedImages.first.imageUrl;
  }

  Map<String, GenerationRunStepPreview> _pipelineStepsByStage() {
    final byStage = <String, GenerationRunStepPreview>{};
    for (final s in _generationRunStepPreviews) {
      final key = canonicalPipelineStageKey(s.stage);
      if (!kPipelineFunnelRecognizedStageKeys.contains(key)) continue;
      byStage[key] = s;
    }
    return byStage;
  }

  List<String> _visiblePipelineStageKeys(
    Map<String, GenerationRunStepPreview> byStage,
  ) {
    return [
      for (final k in kPipelineFunnelCoreStages)
        if (byStage.containsKey(k)) k,
      if (byStage.containsKey('exif_stamp')) 'exif_stamp',
      if (byStage.containsKey('c2pa_sign')) 'c2pa_sign',
      if (byStage.containsKey(kPipelineFunnelStorageStage))
        kPipelineFunnelStorageStage,
    ];
  }

  String? _pipelineDisplayPreviewUrl({
    required String stageKey,
    required String? rawNonEmpty,
    required String? lastShownUrl,
  }) {
    if (rawNonEmpty == null) return null;
    final noDedupe = stageKey == 'frame_composite' ||
        stageKey == kPipelineFunnelStorageStage;
    if (noDedupe || lastShownUrl == null || rawNonEmpty != lastShownUrl) {
      return rawNonEmpty;
    }
    return null;
  }

  PipelineFunnelSlot _pipelineSlotForStage({
    required String stageKey,
    required GenerationRunStepPreview? step,
    required String? displayPreviewUrl,
  }) {
    final isFinished = step?.isFinished ?? false;
    final isActive = step?.isActive ?? false;
    final isPending = step == null || (!isFinished && !isActive);
    return PipelineFunnelSlot(
      stageKey: stageKey,
      label: transformationStepDisplayLabel(stageKey),
      displayPreviewUrl: displayPreviewUrl,
      isPending: isPending,
      isActive: isActive,
      isFinished: isFinished,
      isDeviceCapture: false,
      isMetadataOnlyStage: kPipelineFunnelMetadataOnlyStages.contains(stageKey),
    );
  }

  /// In-frame capture (optional) + core stages + conditional EXIF/C2PA + storage.
  List<PipelineFunnelSlot> get pipelineFunnelSlots {
    final byStage = _pipelineStepsByStage();
    final stageSequence = _visiblePipelineStageKeys(byStage);
    String? lastShownUrl;
    final out = <PipelineFunnelSlot>[];
    if (_originalPhoto != null) {
      out.add(PipelineFunnelSlot(
        stageKey: kPipelineDeviceCaptureStageKey,
        label: transformationStepDisplayLabel(kPipelineDeviceCaptureStageKey),
        displayPreviewUrl: null,
        isPending: false,
        isActive: false,
        isFinished: true,
        isDeviceCapture: true,
      ));
    }
    for (final stageKey in stageSequence) {
      final step = byStage[stageKey];
      final raw = step?.previewUrl?.trim();
      final rawNonEmpty = raw != null && raw.isNotEmpty ? raw : null;
      final display = _pipelineDisplayPreviewUrl(
        stageKey: stageKey,
        rawNonEmpty: rawNonEmpty,
        lastShownUrl: lastShownUrl,
      );
      if (display != null) lastShownUrl = display;
      out.add(_pipelineSlotForStage(
        stageKey: stageKey,
        step: step,
        displayPreviewUrl: display,
      ));
    }
    return List<PipelineFunnelSlot>.unmodifiable(out);
  }

  /// 0–1: finished slots / total slots (dynamic if EXIF/C2PA omitted).
  double get pipelineFunnelProgress {
    final slots = pipelineFunnelSlots;
    if (slots.isEmpty) return 0;
    final done = slots.where((s) => s.isFinished).length;
    return (done / slots.length).clamp(0.0, 1.0);
  }

  /// Progressive filmstrip + stage thumbs: only when pref is on **and** SSE runs (parallel > 1).
  bool get useProgressiveGenerationLayoutForSession =>
      _useProgressiveGenerationUi && _parallelSlotCount > 1;

  int get parallelImageSlotCount => _parallelSlotCount;

  List<ProgressivePipelineStage> get progressivePipelineStages {
    // Only keep stages where we can actually show a thumbnail (no placeholder-only timeline rows).
    final out = _progressivePipelineStages
        .where((s) => (s.previewImageUrl ?? '').trim().isNotEmpty)
        .toList(growable: false);
    return List<ProgressivePipelineStage>.unmodifiable(out);
  }

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
    // Keep POST `/api/generate-image` attempt in sync with the server. After a
    // completed run, [SessionData.attemptsUsed] advances; resetting tries to
    // max here would resend attempt 1 and can trigger API errors when re-entering
    // from theme after backing out of /generate.
    final used = _sessionManager.currentSession?.attemptsUsed ?? 0;
    _triesRemaining = (_maxRegenerationsAllowed - used)
        .clamp(0, _maxRegenerationsAllowed);
    _selectedHeroStampId = null;
    notifyListeners();
  }

  /// Tap a stamp to preview it in the center hero; tap again to clear.
  void toggleHeroStamp(String stampId) {
    if (_selectedHeroStampId == stampId) {
      _selectedHeroStampId = null;
    } else {
      _selectedHeroStampId = stampId;
    }
    notifyListeners();
  }

  void _clearHeroStamp() {
    if (_selectedHeroStampId == null) return;
    _selectedHeroStampId = null;
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

  void _stopGenerationRunPolling() {
    _generationRunPollTimer?.cancel();
    _generationRunPollTimer = null;
  }

  void _startGenerationRunPolling() {
    _stopGenerationRunPolling();
    _generationRunPollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_pollGenerationRunTick()),
    );
    unawaited(_pollGenerationRunTick());
  }

  void _ingestRunIdFromSsePayload(Map<String, dynamic> data) {
    final raw = data['runId'];
    if (raw is! String || raw.trim().isEmpty) return;
    final id = raw.trim();
    if (_polledTransformationRunId == id) return;
    _polledTransformationRunId = id;
    if (_lastTransformationRunId == null || _lastTransformationRunId!.isEmpty) {
      _lastTransformationRunId = id;
    }
    notifyListeners();
  }

  Future<void> _pollGenerationRunTick() async {
    if (!_isGenerating && !_isLoadingMore) return;
    if (_generationRunPollInFlight) return;
    final sid = _sessionManager.sessionId;
    if (sid == null) return;
    _generationRunPollInFlight = true;
    try {
      await _pollResolveTransformationRunId(sid);
      await _pollRefreshGenerationRunStepPreviews();
    } catch (e) {
      AppLogger.debug('Generation run poll: $e');
    } finally {
      _generationRunPollInFlight = false;
    }
  }

  Future<void> _pollResolveTransformationRunId(String sessionId) async {
    if (_polledTransformationRunId != null &&
        _polledTransformationRunId!.trim().isNotEmpty) {
      return;
    }
    final sessionRaw = await _apiService.fetchSession(sessionId);
    final rid = parseActiveTransformationRunIdFromSession(sessionRaw);
    if (rid == null) return;
    _polledTransformationRunId = rid;
    if (_lastTransformationRunId == null || _lastTransformationRunId!.isEmpty) {
      _lastTransformationRunId = rid;
    }
    notifyListeners();
  }

  Future<void> _pollRefreshGenerationRunStepPreviews() async {
    final runId = _polledTransformationRunId?.trim();
    if (runId == null || runId.isEmpty) return;
    final payload = await _apiService.fetchGenerationRun(runId);
    final next = parseGenerationRunStepsFromPayload(payload);
    if (!generationRunStepsEqual(_generationRunStepPreviews, next)) {
      _generationRunStepPreviews = next;
      notifyListeners();
    }
  }

  void _updateProgress(String message) {
    _progressMessage = message;
    notifyListeners();
  }

  void _resetLiveGenerationState() {
    _stopGenerationRunPolling();
    _generationRunStepPreviews = [];
    _polledTransformationRunId = null;
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
    _selectedHeroStampId = null;
  }

  void _clearLiveGenerationUi() {
    _stopGenerationRunPolling();
    _generationRunStepPreviews = [];
    _polledTransformationRunId = null;
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

  /// Clears SSE/live slot noise but keeps [ _generationRunStepPreviews ] for the fixed funnel.
  void _stopEphemeralGenerationUiPreservingFunnel() {
    _stopGenerationRunPolling();
    _polledTransformationRunId = null;
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

  Future<void> _refreshGenerationRunStepsNow() async {
    final runId =
        (_lastTransformationRunId ?? _polledTransformationRunId)?.trim();
    if (runId == null || runId.isEmpty) return;
    if (_generationRunPollInFlight) return;
    _generationRunPollInFlight = true;
    try {
      final payload = await _apiService.fetchGenerationRun(runId);
      final next = parseGenerationRunStepsFromPayload(payload);
      if (!generationRunStepsEqual(_generationRunStepPreviews, next)) {
        _generationRunStepPreviews = next;
        notifyListeners();
      }
    } catch (e) {
      AppLogger.debug('Generation run refresh: $e');
    } finally {
      _generationRunPollInFlight = false;
    }
  }

  String? _extractStepPreviewUrl(Map<String, dynamic> data) {
    return SecureImageUrl.previewUrlFromStepMap(data);
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
    _ingestRunIdFromSsePayload(data);
    switch (event) {
      case 'status':
      case 'start':
        _handleSseStatusOrStart(data);
        break;
      case 'step':
        _handleSseStep(data);
        break;
      case 'attempt_start':
        _handleSseAttemptStart(data);
        break;
      case 'attempt_complete':
        _handleSseAttemptComplete(data);
        break;
      case 'image_complete':
        _handleSseImageComplete(data);
        break;
      case 'image_failed':
        _handleSseImageFailed(data);
        break;
      case 'commentary':
        _handleSseCommentary(data);
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

  void _handleSseStatusOrStart(Map<String, dynamic> data) {
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
  }

  void _handleSseStep(Map<String, dynamic> data) {
    final step = data['step'] as String?;
    if (step == null) return;
    final st = data['status'] as String?;
    final previewUrl = _extractStepPreviewUrl(data);
    if (st == 'active') {
      _liveCurrentStep = step;
      _upsertProgressiveStage(
        step,
        active: true,
        complete: false,
        previewUrl: previewUrl,
      );
    }
    if (st != 'complete') return;
    final skipped = data['skipped'] == true;
    final ms = parseSseDurationMs(data['durationMs']);
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

  void _handleSseAttemptStart(Map<String, dynamic> data) {
    _liveAttempt = (data['attempt'] as num?)?.toInt();
    _liveTotalAttempts = (data['totalAttempts'] as num?)?.toInt();
  }

  void _handleSseAttemptComplete(Map<String, dynamic> data) {
    _liveLastScore = (data['score'] as num?)?.toDouble();
  }

  void _handleSseImageComplete(Map<String, dynamic> data) {
    final idx = parseSseEventIndex(data['index']);
    final rawUrl = data['imageUrl'] as String?;
    final q = (data['qualityScore'] as num?)?.toDouble();
    if (idx != null &&
        idx >= 0 &&
        idx < _liveSlots.length &&
        rawUrl != null &&
        rawUrl.isNotEmpty) {
      final next = List<LiveGenerationSlotState>.from(_liveSlots);
      next[idx] = LiveGenerationSlotState(
        index: idx,
        loading: false,
        failed: false,
        imageUrl: SecureImageUrl.absolutize(rawUrl),
        qualityScore: q,
      );
      _liveSlots = next;
    }
    final c = data['completed'];
    final t = data['total'];
    if (c is num && t is num && t > 0) {
      _liveProgress = math.min(92, 15 + (c / t) * 77);
    }
  }

  void _handleSseImageFailed(Map<String, dynamic> data) {
    final idx = parseSseEventIndex(data['index']);
    if (idx == null || idx < 0 || idx >= _liveSlots.length) return;
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

  void _handleSseCommentary(Map<String, dynamic> data) {
    if (_appSettingsManager?.settings?.showGenerationCommentary != true) {
      return;
    }
    _liveCommentary = data['message'] as String?;
  }

  Future<bool> _completeParallelGeneration(
    ParallelGenerationResult parallel, {
    required ThemeModel theme,
    void Function(bool succeeded)? assignSucceeded,
    void Function()? onSuccessLog,
  }) async {
    if (parallel.firstImageUrl == null) {
      _errorMessage = 'Failed to generate image';
      return false;
    }
    assignSucceeded?.call(true);
    _lastTransformationRunId = parallel.runId;
    try {
      await _refreshGenerationRunStepsNow()
          .timeout(const Duration(milliseconds: 900));
    } catch (_) {}
    final newImages = generatedImagesFromParallelResult(
      parallel: parallel,
      theme: theme,
      newImageId: _newGeneratedImageId,
    );
    _generatedImages = [...newImages, ..._generatedImages];
    _ensureNewestAlwaysSelected();
    _triesRemaining--;
    _clearHeroStamp();
    onSuccessLog?.call();
    return true;
  }

  /// Generate image with the current theme
  Future<bool> generateImage() async {
    if (_selectedTheme == null || _originalPhoto == null) {
      _errorMessage = 'No theme or photo selected';
      notifyListeners();
      return false;
    }
    if (_triesRemaining <= 0) {
      _errorMessage =
          'No generation attempts remaining for this session. Start a new session to continue.';
      notifyListeners();
      return false;
    }

    var succeeded = false;
    _resetCancellation();
    _resetLiveGenerationState();
    _isGenerating = true;
    _errorMessage = null;
    _progressMessage = 'Preparing transformation...';
    notifyListeners();
    
    _startTimer();
    _startGenerationRunPolling();

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

      // If the user pressed back/cancel while the request was in-flight, ignore late results.
      if (_isCancelled) {
        AppLogger.debug('🚫 Generation result ignored (cancelled)');
        return false;
      }

      return await _completeParallelGeneration(
        parallel,
        theme: _selectedTheme!,
        onSuccessLog: () {
          AppLogger.debug('✅ Image generated successfully');
          ErrorReportingManager.log('Image generated successfully');
        },
        assignSucceeded: (v) => succeeded = v,
      );
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
      _errorMessage = generateImageErrorMessage(e);
      return false;
    } finally {
      _stopTimer();
      _isGenerating = false;
      _progressMessage = '';
      if (succeeded) {
        unawaited(_refreshGenerationRunStepsNow());
        _stopEphemeralGenerationUiPreservingFunnel();
      } else {
        _clearLiveGenerationUi();
      }
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

    var succeeded = false;
    _resetCancellation();
    _resetLiveGenerationState();
    _isLoadingMore = true;
    _errorMessage = null;
    _progressMessage = _progressMessage.isNotEmpty ? _progressMessage : 'Trying new style...';
    notifyListeners();
    
    _startTimer();
    _startGenerationRunPolling();

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
        final patch = await _apiService
            .updateSession(
              sessionId: _sessionManager.sessionId!,
              selectedThemeId: newTheme.id,
            )
            .timeout(
              updateTimeout,
              onTimeout: () => throw TimeoutException(
                'Update theme timed out after ${updateTimeout.inSeconds} seconds',
              ),
            );
        _sessionManager.setSessionFromResponse(patch);
        _refreshMaxRegenerationsFromSettings();
        final usedAfter = _sessionManager.currentSession?.attemptsUsed ?? 0;
        _triesRemaining = (_maxRegenerationsAllowed - usedAfter)
            .clamp(0, _maxRegenerationsAllowed);
      } on TimeoutException {
        _errorMessage = 'Request took too long. Please try again.';
        return false;
      } catch (e) {
        _errorMessage = 'Failed to update theme: $e';
        return false;
      }

      if (_triesRemaining <= 0) {
        _errorMessage =
            'No generation attempts remaining for this session. Start a new session to continue.';
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

      // If the user pressed back/cancel while the request was in-flight, ignore late results.
      if (_isCancelled) {
        AppLogger.debug('🚫 Try-different-style result ignored (cancelled)');
        return false;
      }

      return await _completeParallelGeneration(
        parallel,
        theme: newTheme,
        assignSucceeded: (v) => succeeded = v,
      );
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
      _errorMessage = tryDifferentStyleErrorMessage(e);
      return false;
    } finally {
      _stopTimer();
      _isLoadingMore = false;
      _progressMessage = '';
      if (succeeded) {
        unawaited(_refreshGenerationRunStepsNow());
        _stopEphemeralGenerationUiPreservingFunnel();
      } else {
        _clearLiveGenerationUi();
      }
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
    // User-initiated cancel: don't surface as an error snackbar.
    _errorMessage = null;
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
    _stopGenerationRunPolling();
    super.dispose();
  }
}
