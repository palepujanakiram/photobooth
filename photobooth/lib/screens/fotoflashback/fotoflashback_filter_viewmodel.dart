import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/strip_models.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/capture_flow_log.dart';
import '../../utils/classic_strip_scrub_coordinator.dart';
import '../../utils/classic_strip_scrub_helpers.dart';
import '../../utils/constants.dart';
import '../../utils/exceptions.dart';
import '../../utils/logger.dart';
import '../../utils/print_orientation.dart';
import '../../utils/print_size_helpers.dart';
import '../../utils/strip_filters_catalog_fallback.dart';
import '../../utils/strip_look_color_matrices.dart';
import '../../utils/strip_look_matrix_bake.dart';
import '../../utils/strip_preview_grade_compress.dart';
import '../photo_generate/photo_generate_viewmodel.dart';
import '../theme_selection/theme_model.dart';

/// Loads strip looks and composes the dual strip (Gemini AF polish on shots).
class FotoFlashbackFilterViewModel extends ChangeNotifier {
  FotoFlashbackFilterViewModel({
    required this.theme,
    required List<String> imageDataUrls,
    ApiService? apiService,
    SessionManager? sessionManager,
    bool overlayCleanupAlreadyDone = false,
    List<bool> shotCleaned = const [],
    PrintOrientation? printOrientation,
    /// Test-only override for [AppConstants.kEnableStripOverlayCleanup].
    bool? overlayCleanupBuildGate,
  })  : _imageDataUrls = List<String>.from(imageDataUrls),
        _api = apiService ?? ApiService(),
        _sessionManager = sessionManager ?? SessionManager(),
        _previewCleaned = overlayCleanupAlreadyDone,
        _printOrientation = printOrientation ?? PrintOrientation.portrait,
        _overlayCleanupBuildGate = overlayCleanupBuildGate,
        _shotCleaned = List<bool>.generate(
          imageDataUrls.length,
          (i) =>
              overlayCleanupAlreadyDone ||
              (i < shotCleaned.length && shotCleaned[i]),
        );

  final ThemeModel theme;
  List<String> _imageDataUrls;
  final ApiService _api;
  final SessionManager _sessionManager;
  PrintOrientation _printOrientation;
  final bool? _overlayCleanupBuildGate;

  StripFiltersCatalog? _catalog;
  String _selectedFilterId = kDefaultStripFilterId;
  String _selectedFrameId = kDefaultStripFrameId;
  String _selectedStickerId = kDefaultStripStickerId;
  final List<StripStickerPlacement> _placements = [];
  final List<StripScribbleStroke> _scribbles = [];
  List<StripScribblePoint>? _activeScribblePoints;
  bool _drawMode = false;
  String _penColor = kStripScribblePenColors.first;
  final double _penWidth = 0.02;
  bool _loading = false;
  bool _preparingPreview = false;
  bool _previewCleaned = false;
  bool _gradingPreview = false;
  bool _warmingPrintPreview = false;
  bool _composing = false;
  String? _errorMessage;
  StripComposeResult? _composeResult;
  Future<void>? _prepareFuture;
  int _placementSeq = 0;
  int _gradeSeq = 0;
  int _composePreviewSeq = 0;
  int _catalogLoadGen = 0;
  Timer? _composePreviewDebounce;
  String? _composePreviewFingerprint;
  StripComposeResult? _composePreview;
  final Map<String, List<String>> _gradedByFilter = {};
  /// Print-sized Flutter-baked JPEGs keyed by filter id (invalidated with shots).
  final Map<String, List<String>> _bakedByFilter = {};
  String? _bakedShotsKey;
  final List<bool> _shotCleaned;
  int? _scrubbingIndex;
  /// True after at least one look-screen scrub pass finished (success or fail).
  bool _scrubPassCompleted = false;

  /// Raw captures (for compose). Prefer [previewImageDataUrls] for the look UI.
  List<String> get imageDataUrls => List<String>.unmodifiable(_imageDataUrls);

  /// Instant browse: capture bytes + Flutter ColorFilters (same matrices as print).
  List<String> get previewImageDataUrls => imageDataUrls;

  /// Always false — Flutter ColorFilter until [lookComposePreviewUrl] is ready.
  bool get previewImagesAreGraded => false;

  /// Exact print JPEG once background warm finishes (Flutter-baked + compose).
  /// Null while warming → UI keeps instant ColorFilter (same matrices).
  String? get lookComposePreviewUrl {
    final url = _composePreview?.printImageUrl.trim() ?? '';
    if (url.isEmpty) return null;
    if (_composePreviewFingerprint != _lookComposeFingerprint()) return null;
    return url;
  }

  bool get isRefreshingComposePreview => false;

  /// Browse stays interactive — print warm is silent in the background.
  bool get isRefreshingLookPreview => false;

  /// Soft status: print twin is still warming (no dim overlay).
  bool get isWarmingPrintPreview =>
      _hasComposableShotCount && _warmingPrintPreview;

  /// Classic 1-shot print (portrait 4×6 by default; guest can switch to 6×4).
  bool get isSingleClassic => _imageDataUrls.length == 1;

  bool get _hasComposableShotCount =>
      _imageDataUrls.length == 1 ||
      _imageDataUrls.length == kStripShotCount;

  StripWysiwygLayout get wysiwygLayout =>
      _catalog?.wysiwyg ?? StripWysiwygLayout.defaults;

  StripFiltersCatalog? get catalog => _catalog;

  /// Admin master switch from strip catalog + build kill-switch.
  bool get classicOverlayCleanupEnabled {
    final gate =
        _overlayCleanupBuildGate ?? AppConstants.kEnableStripOverlayCleanup;
    if (!gate) return false;
    // Match [classicOverlayScrubEnabled]: unset admin value defaults to ON.
    return (_catalog?.enableOsdScrub) != false;
  }

  List<StripFilter> get filters => _catalog?.filters ?? const [];

  /// Sheet layouts need 4 cells — hide them for Classic 1-shot 6×4.
  List<StripFrame> get frames {
    final all = _catalog?.frames ?? const <StripFrame>[];
    if (!isSingleClassic) return all;
    return all
        .where((f) => !isStripSheetLayout(f.id))
        .toList(growable: false);
  }
  List<StripSticker> get stickers => _catalog?.stickers ?? const [];
  String get selectedFilterId => _selectedFilterId;
  String get selectedFrameId => _selectedFrameId;
  PrintOrientation get printOrientation => _printOrientation;

  /// Landscape 6×4 vs portrait 4×6 — Classic 1-shot only.
  void selectPrintOrientation(PrintOrientation orientation) {
    if (!isSingleClassic) return;
    if (_printOrientation == orientation) return;
    _printOrientation = orientation;
    _sessionManager.setPrintOrientation(orientation);
    notifyListeners();
    _scheduleComposePreview();
  }

  StripFrame? get selectedFrame {
    for (final f in frames) {
      if (f.id == _selectedFrameId) return f;
    }
    return null;
  }

  /// Chip highlight: `none` when empty, else last-added placeable type.
  String get selectedStickerId => _selectedStickerId;

  List<StripStickerPlacement> get stickerPlacements =>
      List<StripStickerPlacement>.unmodifiable(_placements);

  List<StripScribbleStroke> get scribbles {
    final active = _activeScribblePoints;
    if (active == null || active.isEmpty) {
      return List<StripScribbleStroke>.unmodifiable(_scribbles);
    }
    return List<StripScribbleStroke>.unmodifiable([
      ..._scribbles,
      StripScribbleStroke(
        color: _penColor,
        width: _penWidth,
        points: List<StripScribblePoint>.from(active),
      ),
    ]);
  }

  bool get drawMode => _drawMode;
  String get penColor => _penColor;
  double get penWidth => _penWidth;
  bool get canUndoScribble =>
      _scribbles.isNotEmpty || (_activeScribblePoints?.isNotEmpty ?? false);

  bool get isLoading => _loading;
  /// True only while Gemini AF polish is still running (not during grade).
  bool get isPreparingPreview => _preparingPreview;
  bool get previewCleaned => _previewCleaned;

  /// Progress dots for Classic AF polish (capture + look-screen remainder).
  List<ClassicScrubDotStatus> get scrubDotStatuses {
    return [
      for (var i = 0; i < _imageDataUrls.length; i++)
        if (i < _shotCleaned.length && _shotCleaned[i])
          ClassicScrubDotStatus.cleaned
        else if (_preparingPreview && _scrubbingIndex == i)
          ClassicScrubDotStatus.scrubbing
        else if (_preparingPreview)
          ClassicScrubDotStatus.pending
        else if (_scrubPassCompleted)
          ClassicScrubDotStatus.failed
        else
          ClassicScrubDotStatus.pending,
    ];
  }

  /// True when at least one shot still needs AF polish.
  bool get hasUnfinishedScrub =>
      classicOverlayCleanupEnabled &&
      _shotCleaned.any((c) => !c);

  /// Operator may tap Refresh when [hasUnfinishedScrub] after a scrub pass.
  bool get canRetryUnfinishedScrub =>
      hasUnfinishedScrub && !_preparingPreview && !_loading;

  bool get isGradingPreview => _gradingPreview;
  bool get isComposing => _composing;
  String? get errorMessage => _errorMessage;
  StripComposeResult? get composeResult => _composeResult;

  /// Continue stays enabled while the catalog loads — defaults work offline.
  bool get canCompose => _hasComposableShotCount && !_composing;

  StripFilter? get selectedFilter {
    for (final f in filters) {
      if (f.id == _selectedFilterId) return f;
    }
    return null;
  }

  Future<void> loadFilters() async {
    final gen = ++_catalogLoadGen;
    _loading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _loadCatalog(gen).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          if (gen != _catalogLoadGen) return;
          AppLogger.warning('Strip filters catalog timed out after 15s');
          _applyFallbackCatalog(AppStrings.flashbackFiltersLoadTimeout);
        },
      );
    } finally {
      if (gen == _catalogLoadGen) {
        if (_catalog == null || filters.isEmpty) {
          _applyFallbackCatalog(
            _errorMessage ?? AppStrings.flashbackFiltersLoadTimeout,
          );
        }
        _loading = false;
        notifyListeners();
      }
    }
    if (gen != _catalogLoadGen) return;
    if (classicOverlayCleanupEnabled && !_previewCleaned) {
      unawaited(preparePreview().then((_) {
        _scheduleComposePreview();
      }));
    }
    _scheduleComposePreview();
  }

  void _applyFallbackCatalog(String message) {
    _catalog = stripFiltersCatalogFallback();
    _selectedFilterId = kDefaultStripFilterId;
    _selectedFrameId = kDefaultStripFrameId;
    _selectedStickerId = kDefaultStripStickerId;
    _errorMessage = message;
  }

  Future<void> _loadCatalog(int gen) async {
    try {
      final catalog = await _api.fetchStripFilters();
      if (gen != _catalogLoadGen) return;
      _catalog = catalog;
      if (filters.isNotEmpty &&
          !filters.any((f) => f.id == _selectedFilterId)) {
        _selectedFilterId = filters.first.id;
      }
      if (frames.isNotEmpty &&
          (!frames.any((f) => f.id == _selectedFrameId) ||
              (isSingleClassic && isStripSheetLayout(_selectedFrameId)))) {
        _selectedFrameId = frames.first.id;
      }
      if (stickers.isNotEmpty &&
          !stickers.any((s) => s.id == _selectedStickerId) &&
          _placements.isEmpty) {
        _selectedStickerId = kDefaultStripStickerId;
      }
      _errorMessage = null;
    } on ApiException catch (e) {
      if (gen != _catalogLoadGen) return;
      if (filters.isNotEmpty) return;
      _applyFallbackCatalog(e.message);
    } catch (e) {
      if (gen != _catalogLoadGen) return;
      if (filters.isNotEmpty) return;
      _applyFallbackCatalog(e.toString());
    }
  }

  /// Classic overlay polish when admin scrub is ON (Gemini AF + OSD).
  /// Fail-open: keeps originals if cleanup fails. No-op when scrub is OFF.
  Future<void> preparePreview() async {
    if (!classicOverlayCleanupEnabled) return;
    if (_previewCleaned ||
        (_imageDataUrls.length != 1 &&
            _imageDataUrls.length != kStripShotCount)) {
      return;
    }
    final existing = _prepareFuture;
    if (existing != null) return existing;

    final sessionId = _sessionManager.sessionId?.trim() ?? '';
    if (sessionId.isEmpty) return;

    final future = _runPreparePreview(sessionId);
    _prepareFuture = future;
    try {
      await future;
    } finally {
      if (identical(_prepareFuture, future)) {
        _prepareFuture = null;
      }
    }
  }

  /// Operator refresh: re-scrub any shots that are still unfinished.
  Future<void> retryUnfinishedScrub() async {
    if (!canRetryUnfinishedScrub) return;
    _previewCleaned = false;
    _scrubPassCompleted = false;
    _gradedByFilter.clear();
    _bakedByFilter.clear();
    _bakedShotsKey = null;
    // Drop failed capture results so Refresh re-POSTs instead of re-adopting.
    ClassicStripScrubCoordinator.instance.releaseFailedShots();
    notifyListeners();
    await preparePreview();
  }

  Future<void> _runPreparePreview(String sessionId) async {
    _preparingPreview = true;
    notifyListeners();
    CaptureFlowLog.event(
      'classic.scrub_start',
      fields: {
        'session': sessionId,
        'shots': _imageDataUrls.length,
      },
    );
    try {
      // Only re-clean shots that did not finish during capture.
      var allClean = true;
      for (var i = 0; i < _imageDataUrls.length; i++) {
        if (i < _shotCleaned.length && _shotCleaned[i]) {
          continue;
        }
        _scrubbingIndex = i;
        notifyListeners();
        final applied = await _polishUnfinishedShot(sessionId, i);
        if (!applied) allClean = false;
      }
      _scrubbingIndex = null;
      _previewCleaned = allClean &&
          _shotCleaned.length == _imageDataUrls.length &&
          _shotCleaned.every((c) => c);
      CaptureFlowLog.event(
        'classic.scrub_done',
        fields: {
          'session': sessionId,
          'all_clean': _previewCleaned,
        },
      );
    } catch (e) {
      // Preview still usable with originals; compose will clean again.
      CaptureFlowLog.event(
        'classic.scrub_fail_open',
        fields: {'session': sessionId, 'error': '$e'},
        level: LogLevel.warning,
      );
      _previewCleaned = false;
      _scrubbingIndex = null;
    } finally {
      _scrubPassCompleted = true;
      _preparingPreview = false;
      notifyListeners();
    }
  }

  /// Prefer successful in-flight capture scrub over a second Gemini POST.
  /// Failed capture scrubs are ignored so look/Refresh can re-POST.
  Future<bool> _polishUnfinishedShot(String sessionId, int i) async {
    final fromCoord = await _adoptCaptureScrubIfAvailable(i);
    if (fromCoord != null) {
      return _applyScrubResult(i, fromCoord);
    }

    final result = await _api.cleanStripOverlays(
      sessionId: sessionId,
      images: [_imageDataUrls[i]],
    );
    if (result.images.length != 1 || result.images.first.trim().isEmpty) {
      if (i < _shotCleaned.length) _shotCleaned[i] = false;
      return false;
    }
    final shotClean =
        !result.skipped &&
        result.cleanedFlags.length == 1 &&
        result.cleanedFlags.first;
    return _applyScrubResult(
      i,
      ClassicShotScrubResult(
        dataUrl: result.images.first,
        scrubbed: shotClean,
      ),
    );
  }

  Future<ClassicShotScrubResult?> _adoptCaptureScrubIfAvailable(int i) async {
    final coord = ClassicStripScrubCoordinator.instance;
    if (coord.shotCount != _imageDataUrls.length || !coord.hasShot(i)) {
      return null;
    }
    try {
      // Do not wait forever on a stuck capture Gemini call — look can re-POST.
      final result = await coord.awaitShotForAdopt(i).timeout(
        const Duration(seconds: 45),
        onTimeout: () => null,
      );
      if (result == null) return null;
      if (result.dataUrl.trim().isEmpty) return null;
      // Fail-open capture results must not block look-screen re-clean.
      if (!result.scrubbed) return null;
      return result;
    } catch (_) {
      return null;
    }
  }

  bool _applyScrubResult(int i, ClassicShotScrubResult result) {
    _imageDataUrls[i] = result.dataUrl;
    if (i < _shotCleaned.length) _shotCleaned[i] = result.scrubbed;
    _gradedByFilter.clear();
    _bakedByFilter.clear();
    _bakedShotsKey = null;
    notifyListeners();
    return result.scrubbed;
  }

  /// Optional Sharp grade cache (look UI no longer displays these thumbs —
  /// Flutter ColorFilters browse instead). Kept for Continue-path experiments
  /// and unit coverage of the grade API.
  Future<void> refreshPreviewGrade() async {
    if (_imageDataUrls.length != kStripShotCount) return;
    final filterId = _selectedFilterId;
    final cached = _gradedByFilter[filterId];
    if (cached != null && cached.length == kStripShotCount) return;

    final sessionId = _sessionManager.sessionId?.trim() ?? '';
    if (sessionId.isEmpty) return;

    final seq = ++_gradeSeq;
    _gradingPreview = true;
    notifyListeners();
    try {
      // Cap uploads below full Canon plates, but high enough for sharp tablet
      // look-picker cells (see [kStripPreviewGradeUploadMaxEdge]).
      final gradeInputs = await compressDataUrlsForStripPreviewGrade(
        List<String>.from(_imageDataUrls),
      );
      if (seq != _gradeSeq) return;
      final graded = await _api.gradeStripPreview(
        sessionId: sessionId,
        images: gradeInputs,
        filter: filterId,
      );
      if (seq != _gradeSeq) return;
      if (graded.length == kStripShotCount) {
        _gradedByFilter[filterId] = List<String>.from(graded);
      }
    } catch (_) {
      // Fall back to ColorFilter / raw bytes until compose.
    } finally {
      if (seq == _gradeSeq) {
        _gradingPreview = false;
        notifyListeners();
      }
    }
  }

  void selectFilter(String filterId) {
    if (filterId == _selectedFilterId) return;
    _selectedFilterId = filterId;
    notifyListeners();
    // Instant Flutter ColorFilter browse; compose warms for Continue / print.
    _scheduleComposePreview();
  }

  void selectFrame(String frameId) {
    if (isSingleClassic && isStripSheetLayout(frameId)) return;
    if (frameId == _selectedFrameId) return;
    final wasSheet = isStripSheetLayout(_selectedFrameId);
    final nowSheet = isStripSheetLayout(frameId);
    _selectedFrameId = frameId;
    // Strip vs sheet use different normalized spaces — reset overlays.
    if (wasSheet != nowSheet) {
      _placements.clear();
      _scribbles.clear();
      _activeScribblePoints = null;
      _selectedStickerId = kDefaultStripStickerId;
      _drawMode = false;
    }
    notifyListeners();
    _scheduleComposePreview();
  }

  /// Tap a sticker chip: `none` clears; placeable types add one per photo cell.
  void selectSticker(String stickerId) {
    if (stickerId == kDefaultStripStickerId || stickerId == 'none') {
      clearStickers();
      return;
    }
    addSticker(stickerId);
  }

  /// Places stickers on each photo cell (or one placement for Classic 1-shot).
  void addSticker(String type) {
    if (!kPlaceableStripStickerIds.contains(type)) return;

    final room = kMaxStripStickerPlacements - _placements.length;
    if (room <= 0) return;

    final cells = isSingleClassic ? 1 : kStripShotCount;
    final toAdd = room < cells ? room : cells;
    final wave = cells == 0
        ? 0
        : _placements.where((p) => p.type == type).length ~/ cells;
    for (var cell = 0; cell < toAdd; cell++) {
      final spawn = isSingleClassic
          ? _spawnPointForSingle(type, wave)
          : _spawnPointForCell(type, cell, wave);
      _placementSeq += 1;
      _placements.add(
        StripStickerPlacement(
          id: 'sticker_$_placementSeq',
          type: type,
          x: spawn.$1,
          y: spawn.$2,
        ),
      );
    }
    _selectedStickerId = type;
    notifyListeners();
    _scheduleComposePreview();
  }

  void moveSticker(String id, double x, double y) {
    final i = _placements.indexWhere((p) => p.id == id);
    if (i < 0) return;
    final nx = x.clamp(0.05, 0.95);
    final ny = y.clamp(0.05, 0.95);
    final cur = _placements[i];
    if (cur.x == nx && cur.y == ny) return;
    _placements[i] = cur.copyWith(x: nx, y: ny);
    notifyListeners();
    _scheduleComposePreview();
  }

  void removeSticker(String id) {
    final before = _placements.length;
    _placements.removeWhere((p) => p.id == id);
    if (_placements.length == before) return;
    _selectedStickerId =
        _placements.isEmpty ? kDefaultStripStickerId : _placements.last.type;
    notifyListeners();
    _scheduleComposePreview();
  }

  void clearStickers() {
    if (_placements.isEmpty && _selectedStickerId == kDefaultStripStickerId) {
      return;
    }
    _placements.clear();
    _selectedStickerId = kDefaultStripStickerId;
    notifyListeners();
    _scheduleComposePreview();
  }

  void setDrawMode(bool enabled) {
    if (_drawMode == enabled) return;
    if (!enabled) {
      _commitActiveScribble();
      _scheduleComposePreview();
    }
    _drawMode = enabled;
    notifyListeners();
  }

  void setPenColor(String color) {
    final normalized = color.toUpperCase();
    if (!kStripScribblePenColors.contains(normalized)) return;
    if (_penColor == normalized) return;
    _penColor = normalized;
    notifyListeners();
  }

  void beginScribble(double x, double y) {
    if (!_drawMode || _scribbles.length >= kMaxStripScribbleStrokes) return;
    _activeScribblePoints = [
      StripScribblePoint(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0)),
    ];
    notifyListeners();
  }

  void extendScribble(double x, double y) {
    final active = _activeScribblePoints;
    if (active == null || active.length >= kMaxStripScribblePoints) return;
    final nx = x.clamp(0.0, 1.0);
    final ny = y.clamp(0.0, 1.0);
    final last = active.last;
    if ((last.x - nx).abs() < 0.004 && (last.y - ny).abs() < 0.004) return;
    active.add(StripScribblePoint(nx, ny));
    notifyListeners();
  }

  void endScribble() {
    _commitActiveScribble();
    notifyListeners();
    _scheduleComposePreview();
  }

  void undoScribble() {
    if (_activeScribblePoints != null) {
      _activeScribblePoints = null;
      notifyListeners();
      return;
    }
    if (_scribbles.isEmpty) return;
    _scribbles.removeLast();
    notifyListeners();
    _scheduleComposePreview();
  }

  void clearScribbles() {
    if (_scribbles.isEmpty && _activeScribblePoints == null) return;
    _scribbles.clear();
    _activeScribblePoints = null;
    notifyListeners();
    _scheduleComposePreview();
  }

  @visibleForTesting
  set selectedFrameIdForTests(String frameId) => _selectedFrameId = frameId;

  void _commitActiveScribble() {
    final active = _activeScribblePoints;
    _activeScribblePoints = null;
    if (active == null || active.length < 2) return;
    if (_scribbles.length >= kMaxStripScribbleStrokes) return;
    _scribbles.add(
      StripScribbleStroke(
        color: _penColor,
        width: _penWidth,
        points: List<StripScribblePoint>.from(active),
      ),
    );
  }

  /// Composes the strip and returns a selected [GeneratedImage] for Result.
  Future<GeneratedImage?> compose() async {
    if (!canCompose) {
      _errorMessage = isSingleClassic
          ? AppStrings.flashbackComposeFailed
          : AppStrings.flashbackNeedFourShots;
      notifyListeners();
      return null;
    }
    final sessionId = _sessionManager.sessionId?.trim() ?? '';
    if (sessionId.isEmpty) {
      _errorMessage = AppStrings.sessionPhotoSyncNoSession;
      notifyListeners();
      return null;
    }

    _composing = true;
    _errorMessage = null;
    notifyListeners();
    try {
      if (classicOverlayCleanupEnabled) {
        // Finish background polish if still running so print matches preview.
        await preparePreview();
      }
      _commitActiveScribble();
      _sessionManager.setPrintOrientation(_printOrientation);

      final fingerprint = _lookComposeFingerprint();
      final reuse = isSingleClassic &&
          _composePreview != null &&
          _composePreviewFingerprint == fingerprint &&
          (_composePreview!.printImageUrl.trim().isNotEmpty);
      final result = reuse
          ? _composePreview!
          : await _requestComposeStrip(sessionId);
      _composeResult = result;
      _composePreview = result;
      _composePreviewFingerprint = fingerprint;
      final printSize = resolveClassicComposePrintSize(
        imageCount: _imageDataUrls.length,
        apiPrintSize: result.printSize,
        orientation: _printOrientation,
      );
      return GeneratedImage(
        id: 'strip_${_selectedFilterId}_${DateTime.now().millisecondsSinceEpoch}',
        imageUrl: result.printImageUrl,
        theme: theme,
        isSelected: true,
        printSize: printSize,
      );
    } on ApiException catch (e) {
      _errorMessage = e.message;
      return null;
    } catch (_) {
      _errorMessage = AppStrings.flashbackComposeFailed;
      return null;
    } finally {
      _composing = false;
      notifyListeners();
    }
  }

  String _lookComposeFingerprint() {
    final shots = [
      for (final url in _imageDataUrls) '${url.length}:${url.hashCode}',
    ].join(',');
    final placements = [
      for (final p in _placements) '${p.type}:${p.x.toStringAsFixed(3)}:${p.y.toStringAsFixed(3)}',
    ].join('|');
    final scribbles = [
      for (final s in _scribbles)
        '${s.color}:${s.width}:${s.points.length}',
    ].join('|');
    return [
      _selectedFilterId,
      _selectedFrameId,
      _printOrientation.apiValue,
      shots,
      placements,
      scribbles,
      '$_previewCleaned',
    ].join('::');
  }

  void _scheduleComposePreview() {
    if (!_hasComposableShotCount) return;
    _composePreviewDebounce?.cancel();
    // Short debounce: browse is already instant via ColorFilter; this only
    // warms the exact print twin in the background.
    _composePreviewDebounce = Timer(const Duration(milliseconds: 280), () {
      unawaited(refreshComposePreview());
    });
  }

  /// Background: bake print-sized Flutter look + compose so Continue / Your
  /// prints / DNP reuse the same JPEG. Does not block the look browser.
  Future<void> refreshComposePreview() async {
    if (!_hasComposableShotCount || _composing) return;
    final sessionId = _sessionManager.sessionId?.trim() ?? '';
    if (sessionId.isEmpty) return;

    final fingerprint = _lookComposeFingerprint();
    if (_composePreviewFingerprint == fingerprint &&
        (_composePreview?.printImageUrl.trim().isNotEmpty ?? false)) {
      return;
    }

    final seq = ++_composePreviewSeq;
    _warmingPrintPreview = true;
    notifyListeners();
    try {
      _commitActiveScribble();
      _sessionManager.setPrintOrientation(_printOrientation);
      final result = await _requestComposeStrip(sessionId);
      if (seq != _composePreviewSeq) return;
      _composePreview = result;
      _composePreviewFingerprint = fingerprint;
      _composeResult = result;
    } catch (_) {
      // Keep Flutter ColorFilter chrome until Continue compose.
    } finally {
      if (seq == _composePreviewSeq) {
        _warmingPrintPreview = false;
        notifyListeners();
      }
    }
  }

  String _shotsBakeCacheKey() => [
        for (final url in _imageDataUrls) '${url.length}:${url.hashCode}',
      ].join(',');

  Future<List<String>> _bakedImagesForSelectedLook() async {
    final shotsKey = _shotsBakeCacheKey();
    if (_bakedShotsKey != shotsKey) {
      _bakedByFilter.clear();
      _bakedShotsKey = shotsKey;
    }
    final cached = _bakedByFilter[_selectedFilterId];
    if (cached != null && cached.length == _imageDataUrls.length) {
      return cached;
    }
    final baked = await bakeStripLookMatricesOntoDataUrls(
      dataUrls: _imageDataUrls,
      filterId: _selectedFilterId,
    );
    _bakedByFilter[_selectedFilterId] = baked;
    return baked;
  }

  Future<StripComposeResult> _requestComposeStrip(String sessionId) async {
    // Print-sized Flutter bake (cached per look) + identity server grade so
    // Sharp does not wash Classic Warm. Frame/stickers/layout still server-side.
    final images = await _bakedImagesForSelectedLook();
    return _api.composeStrip(
      sessionId: sessionId,
      images: images,
      filter: kStripComposePreBakedFilterId,
      frame: _selectedFrameId,
      sticker: kDefaultStripStickerId,
      stickerPlacements: _placements,
      scribbles: _scribbles,
      cleanOverlays: classicOverlayCleanupEnabled && !_previewCleaned,
      orientation: _printOrientation,
    );
  }

  @override
  void dispose() {
    _composePreviewDebounce?.cancel();
    super.dispose();
  }

  /// Normalized center for Classic 1-shot landscape 6×4.
  (double, double) _spawnPointForSingle(String type, int wave) {
    final waveNudge = (wave % 3) * 0.05;
    final preferLeft = switch (type) {
      'sparkles' || 'flowers' => true,
      'stars' => false,
      _ => wave.isEven,
    };
    final baseX = preferLeft ? 0.22 : 0.78;
    final x = baseX + (preferLeft ? waveNudge : -waveNudge);
    final y = 0.55 + (wave % 2) * 0.08;
    return (x.clamp(0.08, 0.92), y.clamp(0.12, 0.88));
  }

  /// Normalized center inside photo cell [cell] (0–3). [wave] offsets later taps.
  (double, double) _spawnPointForCell(String type, int cell, int wave) {
    if (isStripSheetLayout(_selectedFrameId)) {
      return _spawnPointForSheetCell(type, cell, wave);
    }
    final cellCenterY = (cell + 0.5) / kStripShotCount;
    final waveNudge = (wave % 3) * 0.04;
    final preferLeft = switch (type) {
      'sparkles' || 'flowers' => cell.isEven,
      'stars' => !cell.isEven,
      _ => !cell.isEven, // hearts
    };
    final baseX = preferLeft ? 0.2 : 0.78;
    final x = baseX + (preferLeft ? waveNudge : -waveNudge);
    final yNudge = switch (type) {
      'sparkles' => -0.06,
      'stars' || 'flowers' => 0.02,
      _ => 0.04,
    };
    final y = cellCenterY + yNudge - waveNudge * 0.5;
    return (x.clamp(0.08, 0.92), y.clamp(0.06, 0.94));
  }

  /// Spawn in sheet photo cells (normalized 0–1 on the 4×6).
  (double, double) _spawnPointForSheetCell(String type, int cell, int wave) {
    final layout = wysiwygLayout;
    final waveNudge = (wave % 3) * 0.02;
    final preferRight = switch (type) {
      'sparkles' || 'flowers' => cell.isEven,
      _ => !cell.isEven,
    };
    final fx = preferRight ? 0.72 : 0.28;
    final fy = 0.22 + (type.hashCode % 5) * 0.02;

    late final double left;
    late final double top;
    late final double width;
    late final double height;
    final i = cell.clamp(0, 3);
    if (_selectedFrameId == 'romantic') {
      final slot = layout.romanticSlots[i];
      left = slot.left;
      top = slot.top;
      width = slot.width;
      height = slot.height;
    } else if (_selectedFrameId == 'polaroid') {
      final slot = layout.polaroidSlots[i];
      left = slot.left;
      top = slot.top;
      width = layout.polaroidFrameW;
      height = layout.polaroidFrameH;
    } else if (_selectedFrameId == 'grid_2x2') {
      final margin = layout.gridMargin;
      final gap = layout.gridGap;
      final headerH = layout.gridHeaderH;
      final footerH = layout.gridFooterH;
      final cellW = (1 - margin * 2 - gap) / 2;
      final cellH = (1 - headerH - footerH - margin - gap) / 2;
      final col = i % 2;
      final row = i ~/ 2;
      left = margin + col * (cellW + gap);
      top = headerH + row * (cellH + gap);
      width = cellW;
      height = cellH;
    } else {
      left = 0.1;
      top = 0.1 + i * 0.2;
      width = 0.35;
      height = 0.2;
    }

    final x = left + width * fx + (preferRight ? waveNudge : -waveNudge);
    final y = top + height * fy;
    return (x.clamp(0.05, 0.95), y.clamp(0.05, 0.95));
  }
}
