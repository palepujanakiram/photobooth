import 'package:flutter/foundation.dart';

import '../../models/strip_models.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/exceptions.dart';
import '../photo_generate/photo_generate_viewmodel.dart';
import '../theme_selection/theme_model.dart';

/// Loads strip looks and composes the dual 2×6 print sheet.
class FotoFlashbackFilterViewModel extends ChangeNotifier {
  FotoFlashbackFilterViewModel({
    required this.theme,
    required List<String> imageDataUrls,
    ApiService? apiService,
    SessionManager? sessionManager,
  })  : _imageDataUrls = List<String>.unmodifiable(imageDataUrls),
        _api = apiService ?? ApiService(),
        _sessionManager = sessionManager ?? SessionManager();

  final ThemeModel theme;
  final List<String> _imageDataUrls;
  final ApiService _api;
  final SessionManager _sessionManager;

  StripFiltersCatalog? _catalog;
  String _selectedFilterId = kDefaultStripFilterId;
  bool _loading = false;
  bool _composing = false;
  String? _errorMessage;
  StripComposeResult? _composeResult;

  List<String> get imageDataUrls => _imageDataUrls;
  StripFiltersCatalog? get catalog => _catalog;
  List<StripFilter> get filters => _catalog?.filters ?? const [];
  String get selectedFilterId => _selectedFilterId;
  bool get isLoading => _loading;
  bool get isComposing => _composing;
  String? get errorMessage => _errorMessage;
  StripComposeResult? get composeResult => _composeResult;
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
      _catalog = await _api.fetchStripFilters();
      if (filters.isNotEmpty &&
          !filters.any((f) => f.id == _selectedFilterId)) {
        _selectedFilterId = filters.first.id;
      }
    } on ApiException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void selectFilter(String filterId) {
    if (filterId == _selectedFilterId) return;
    _selectedFilterId = filterId;
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
      final result = await _api.composeStrip(
        sessionId: sessionId,
        images: _imageDataUrls,
        filter: _selectedFilterId,
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
}
