import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/strip_models.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../utils/exceptions.dart';
import '../../utils/print_size_helpers.dart';
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
  })  : _imageDataUrls = List<String>.from(imageDataUrls),
        _api = apiService ?? ApiService(),
        _sessionManager = sessionManager ?? SessionManager(),
        _previewCleaned = overlayCleanupAlreadyDone;

  final ThemeModel theme;
  List<String> _imageDataUrls;
  final ApiService _api;
  final SessionManager _sessionManager;

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
  bool _composing = false;
  String? _errorMessage;
  StripComposeResult? _composeResult;
  Future<void>? _prepareFuture;
  int _placementSeq = 0;
  int _gradeSeq = 0;
  final Map<String, List<String>> _gradedByFilter = {};

  /// Raw captures (for compose). Prefer [previewImageDataUrls] for the look UI.
  List<String> get imageDataUrls => List<String>.unmodifiable(_imageDataUrls);

  /// Sharp-graded thumbs for the selected look when available (Option A).
  List<String> get previewImageDataUrls {
    final graded = _gradedByFilter[_selectedFilterId];
    final expected = _imageDataUrls.length;
    if (graded != null && graded.length == expected) {
      return List<String>.unmodifiable(graded);
    }
    return imageDataUrls;
  }

  bool get previewImagesAreGraded =>
      (_gradedByFilter[_selectedFilterId]?.length ?? 0) ==
      _imageDataUrls.length;

  /// Classic 1-shot landscape 6×4 (vs 4-shot dual strip / sheet).
  bool get isSingleClassic => _imageDataUrls.length == 1;

  bool get _hasComposableShotCount =>
      _imageDataUrls.length == 1 ||
      _imageDataUrls.length == kStripShotCount;

  StripWysiwygLayout get wysiwygLayout =>
      _catalog?.wysiwyg ?? StripWysiwygLayout.defaults;

  StripFiltersCatalog? get catalog => _catalog;

  /// Admin master switch from strip catalog + build kill-switch.
  bool get classicOverlayCleanupEnabled =>
      AppConstants.kEnableStripOverlayCleanup &&
      (_catalog?.enableOsdScrub ?? false);

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
  bool get isPreparingPreview => _preparingPreview || _gradingPreview;
  bool get previewCleaned => _previewCleaned;
  bool get isGradingPreview => _gradingPreview;
  bool get isComposing => _composing;
  String? get errorMessage => _errorMessage;
  StripComposeResult? get composeResult => _composeResult;

  /// Look picker stays interactive while polish runs in the background.
  bool get canCompose =>
      _hasComposableShotCount && !_composing && !_loading;

  StripFilter? get selectedFilter {
    for (final f in filters) {
      if (f.id == _selectedFilterId) return f;
    }
    return null;
  }

  Future<void> loadFilters() async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _loadCatalog();
    } finally {
      _loading = false;
      notifyListeners();
    }
    if (classicOverlayCleanupEnabled && !_previewCleaned) {
      // Polish first (serialized per shot), then grade — avoids freezing dirty AF
      // thumbs under the look while Gemini is still running.
      unawaited(preparePreview().then((_) {
        unawaited(refreshPreviewGrade());
      }));
    } else {
      unawaited(refreshPreviewGrade());
    }
  }

  Future<void> _loadCatalog() async {
    try {
      _catalog = await _api.fetchStripFilters();
      if (filters.isNotEmpty &&
          !filters.any((f) => f.id == _selectedFilterId)) {
        _selectedFilterId = filters.first.id;
      }
      if (frames.isNotEmpty &&
          !frames.any((f) => f.id == _selectedFrameId)) {
        _selectedFrameId = frames.first.id;
      }
      if (isSingleClassic && isStripSheetLayout(_selectedFrameId)) {
        _selectedFrameId = frames.isNotEmpty
            ? frames.first.id
            : kDefaultStripFrameId;
      }
      if (stickers.isNotEmpty &&
          !stickers.any((s) => s.id == _selectedStickerId) &&
          _placements.isEmpty) {
        _selectedStickerId = kDefaultStripStickerId;
      }
    } on ApiException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = e.toString();
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

  Future<void> _runPreparePreview(String sessionId) async {
    _preparingPreview = true;
    notifyListeners();
    try {
      // One shot at a time so the strip updates progressively and we never
      // stamp "_previewCleaned" after a partial/fail-open batch.
      var allClean = true;
      for (var i = 0; i < _imageDataUrls.length; i++) {
        final result = await _api.cleanStripOverlays(
          sessionId: sessionId,
          images: [_imageDataUrls[i]],
        );
        if (result.images.length != 1 || result.images.first.trim().isEmpty) {
          allClean = false;
          continue;
        }
        _imageDataUrls[i] = result.images.first;
        final shotClean =
            !result.skipped &&
            result.cleanedFlags.length == 1 &&
            result.cleanedFlags.first;
        if (!shotClean) allClean = false;
        _gradedByFilter.clear();
        notifyListeners();
      }
      _previewCleaned = allClean;
    } catch (_) {
      // Preview still usable with originals; compose will clean again.
      _previewCleaned = false;
    } finally {
      _preparingPreview = false;
      notifyListeners();
    }
  }

  /// Sharp-grade the four shots for the current look (WYSIWYG Option A).
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
      final graded = await _api.gradeStripPreview(
        sessionId: sessionId,
        images: _imageDataUrls,
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
    unawaited(refreshPreviewGrade());
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
  }

  void removeSticker(String id) {
    final before = _placements.length;
    _placements.removeWhere((p) => p.id == id);
    if (_placements.length == before) return;
    _selectedStickerId =
        _placements.isEmpty ? kDefaultStripStickerId : _placements.last.type;
    notifyListeners();
  }

  void clearStickers() {
    if (_placements.isEmpty && _selectedStickerId == kDefaultStripStickerId) {
      return;
    }
    _placements.clear();
    _selectedStickerId = kDefaultStripStickerId;
    notifyListeners();
  }

  void setDrawMode(bool enabled) {
    if (_drawMode == enabled) return;
    if (!enabled) {
      _commitActiveScribble();
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
  }

  void clearScribbles() {
    if (_scribbles.isEmpty && _activeScribblePoints == null) return;
    _scribbles.clear();
    _activeScribblePoints = null;
    notifyListeners();
  }

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

      final result = await _api.composeStrip(
        sessionId: sessionId,
        images: _imageDataUrls,
        filter: _selectedFilterId,
        frame: _selectedFrameId,
        sticker: kDefaultStripStickerId,
        stickerPlacements: _placements,
        scribbles: _scribbles,
        // Clean at compose only if look polish did not finish — skip entirely
        // when admin scrub is OFF (server also gates on enableOsdScrub).
        cleanOverlays:
            classicOverlayCleanupEnabled && !_previewCleaned,
      );
      _composeResult = result;
      final printSize = resolveClassicComposePrintSize(
        imageCount: _imageDataUrls.length,
        apiPrintSize: result.printSize,
      );
      return GeneratedImage(
        id: 'strip_${result.filter}_${DateTime.now().millisecondsSinceEpoch}',
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

  /// Normalized center for Classic 1-shot landscape 6×4.
  (double, double) _spawnPointForSingle(String type, int wave) {
    final waveNudge = (wave % 3) * 0.05;
    final preferLeft = switch (type) {
      'sparkles' || 'confetti' || 'flowers' => true,
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
      'sparkles' || 'confetti' || 'flowers' => cell.isEven,
      'stars' => !cell.isEven,
      _ => !cell.isEven, // hearts
    };
    final baseX = preferLeft ? 0.2 : 0.78;
    final x = baseX + (preferLeft ? waveNudge : -waveNudge);
    final yNudge = switch (type) {
      'sparkles' => -0.06,
      'confetti' => -0.02,
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
      'sparkles' || 'confetti' || 'flowers' => cell.isEven,
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
