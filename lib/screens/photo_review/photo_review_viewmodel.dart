import 'package:flutter/foundation.dart';
import '../photo_capture/photo_model.dart';
import '../theme_selection/theme_model.dart';
import '../result/transformed_image_model.dart';
import '../../services/api_service.dart';
import '../../utils/exceptions.dart';

class ReviewViewModel extends ChangeNotifier {
  final ApiService _apiService;
  final PhotoModel? _photo;
  final ThemeModel? _theme;
  TransformedImageModel? _transformedImage;
  bool _isTransforming = false;
  String? _errorMessage;

  ReviewViewModel({
    required PhotoModel photo,
    required ThemeModel theme,
    ApiService? apiService,
  })  : _photo = photo,
        _theme = theme,
        _apiService = apiService ?? ApiService();

  PhotoModel? get photo => _photo;
  ThemeModel? get theme => _theme;
  TransformedImageModel? get transformedImage => _transformedImage;
  bool get isTransforming => _isTransforming;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;

  /// Transforms the photo using the selected theme
  Future<TransformedImageModel?> transformPhoto() async {
    if (_photo == null || _theme == null) {
      _errorMessage = 'Photo or theme not set';
      notifyListeners();
      return null;
    }

    _isTransforming = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _transformedImage = await _apiService.transformImage(
        image: _photo!.imageFile,
        theme: _theme!,
        originalPhotoId: _photo!.id,
      );
      notifyListeners();
      return _transformedImage;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      return null;
    } catch (e) {
      _errorMessage = 'Failed to transform photo: $e';
      notifyListeners();
      return null;
    } finally {
      _isTransforming = false;
      notifyListeners();
    }
  }
}

