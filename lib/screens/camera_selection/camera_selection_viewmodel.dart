import 'package:flutter/foundation.dart';
import 'camera_info_model.dart';
import '../../services/camera_service.dart';
import '../../utils/exceptions.dart';

class CameraViewModel extends ChangeNotifier {
  final CameraService _cameraService;
  List<CameraInfoModel> _availableCameras = [];
  CameraInfoModel? _selectedCamera;
  bool _isLoading = false;
  String? _errorMessage;

  CameraViewModel({CameraService? cameraService})
      : _cameraService = cameraService ?? CameraService();

  List<CameraInfoModel> get availableCameras => _availableCameras;
  CameraInfoModel? get selectedCamera => _selectedCamera;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;

  /// Loads available cameras
  Future<void> loadCameras() async {
    _setLoading(true);
    _errorMessage = null;

    try {
      _availableCameras = await _cameraService.getAvailableCameras();
      if (_availableCameras.isNotEmpty && _selectedCamera == null) {
        _selectedCamera = _availableCameras.first;
      }
      notifyListeners();
    } on CameraException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load cameras: $e';
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  /// Selects a camera
  void selectCamera(CameraInfoModel camera) {
    _selectedCamera = camera;
    _errorMessage = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}

