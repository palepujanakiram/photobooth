import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/strip_models.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/exceptions.dart';
import '../photo_generate/photo_generate_viewmodel.dart';
import '../theme_selection/theme_model.dart';

/// Loads strip looks, cleans viewfinder overlays for preview, then composes.
class FotoFlashbackFilterViewModel extends ChangeNotifier {
  FotoFlashbackFilterViewModel({
    required this.theme,
    required List<String> imageDataUrls,
    ApiService? apiService,
    SessionManager? sessionManager,
  })  : _imageDataUrls = List<String>.from(imageDataUrls),
        _api = apiService ?? ApiService(),
        _sessionManager = sessionManager ?? SessionManager();

  final ThemeModel theme;
  List<String> _imageDataUrls;
  final ApiService _api;
  final SessionManager _sessionManager;

  StripFiltersCatalog? _catalog;
  String _selectedFilterId = kDefaultStripFilterId;
  String _selectedFrameId = kDefaultStripFrameId;
  String _selectedStickerId = kDefaultStripStickerId;
  final List<StripStickerPlacement> _placements = [];
  bool _loading = false;
  bool _preparingPreview = false;
  bool _previewCleaned = false;
  bool _composing = false;
  String? _errorMessage;
  StripComposeResult? _composeResult;
  Future<void>? _prepareFuture;
  int _placementSeq = 0;

  List<String> get imageDataUrls => List<String>.unmodifiable(_imageDataUrls);
  StripFiltersCatalog? get catalog => _catalog;
  List<StripFilter> get filters => _catalog?.filters ?? const [];
  List<StripFrame> get frames => _catalog?.frames ?? const [];
  List<StripSticker> get stickers => _catalog?.stickers ?? const [];
  String get selectedFilterId => _selectedFilterId;
  String get selectedFrameId => _selectedFrameId;

  /// Chip highlight: `none` when empty, else last-added placeable type.
  String get selectedStickerId => _selectedStickerId;

  List<StripStickerPlacement> get stickerPlacements =>
      List<StripStickerPlacement>.unmodifiable(_placements);

  bool get isLoading => _loading;
  bool get isPreparingPreview => _preparingPreview;
  bool get previewCleaned => _previewCleaned;
  bool get isComposing => _composing;
  String? get errorMessage => _errorMessage;
  StripComposeResult? get composeResult => _composeResult;

  /// Look picker stays interactive while polish runs in the background.
  bool get canCompose =>
      _imageDataUrls.length == kStripShotCount && !_composing && !_loading;

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
    // Non-blocking: show looks immediately; swap in cleaned shots when ready.
    unawaited(preparePreview());
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

  /// Gemini viewfinder cleanup so the look/pay preview matches print.
  /// Fail-open: keeps originals if cleanup fails.
  Future<void> preparePreview() async {
    if (_previewCleaned || _imageDataUrls.length != kStripShotCount) return;
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
      final cleaned = await _api.cleanStripOverlays(
        sessionId: sessionId,
        images: _imageDataUrls,
      );
      if (cleaned.length == kStripShotCount) {
        _imageDataUrls = List<String>.from(cleaned);
        _previewCleaned = true;
      }
    } catch (_) {
      // Preview still usable with originals; compose will clean again.
    } finally {
      _preparingPreview = false;
      notifyListeners();
    }
  }

  void selectFilter(String filterId) {
    if (filterId == _selectedFilterId) return;
    _selectedFilterId = filterId;
    notifyListeners();
  }

  void selectFrame(String frameId) {
    if (frameId == _selectedFrameId) return;
    _selectedFrameId = frameId;
    notifyListeners();
  }

  /// Tap a sticker chip: `none` clears; placeable types add another instance.
  void selectSticker(String stickerId) {
    if (stickerId == kDefaultStripStickerId || stickerId == 'none') {
      clearStickers();
      return;
    }
    addSticker(stickerId);
  }

  void addSticker(String type) {
    if (!kPlaceableStripStickerIds.contains(type)) return;
    if (_placements.length >= kMaxStripStickerPlacements) return;

    final sameTypeCount = _placements.where((p) => p.type == type).length;
    final spawn = _spawnPoint(type, sameTypeCount);
    _placementSeq += 1;
    _placements.add(
      StripStickerPlacement(
        id: 'sticker_$_placementSeq',
        type: type,
        x: spawn.$1,
        y: spawn.$2,
      ),
    );
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

  /// Composes the strip and returns a selected [GeneratedImage] for Result.
  Future<GeneratedImage?> compose() async {
    if (!canCompose) {
      _errorMessage = AppStrings.flashbackNeedFourShots;
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
      // Finish background polish if still running so print matches preview.
      await preparePreview();

      final result = await _api.composeStrip(
        sessionId: sessionId,
        images: _imageDataUrls,
        filter: _selectedFilterId,
        frame: _selectedFrameId,
        sticker: kDefaultStripStickerId,
        stickerPlacements: _placements,
        // Skip second Gemini pass when preview already cleaned.
        cleanOverlays: !_previewCleaned,
      );
      _composeResult = result;
      return GeneratedImage(
        id: 'strip_${result.filter}_${DateTime.now().millisecondsSinceEpoch}',
        imageUrl: result.printImageUrl,
        theme: theme,
        isSelected: true,
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

  (double, double) _spawnPoint(String type, int sameTypeCount) {
    final offset = sameTypeCount * 0.05;
    switch (type) {
      case 'sparkles':
        return (
          (0.22 + offset).clamp(0.08, 0.9),
          (0.12 + offset * 0.8).clamp(0.08, 0.9),
        );
      case 'date':
        return (
          (0.5 + (sameTypeCount.isEven ? offset : -offset)).clamp(0.2, 0.8),
          (0.88 - offset * 0.5).clamp(0.15, 0.92),
        );
      case 'hearts':
      default:
        return (
          (0.7 - offset).clamp(0.08, 0.9),
          (0.14 + offset).clamp(0.08, 0.9),
        );
    }
  }
}
