import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../../models/strip_models.dart';
import '../photo_capture/photo_model.dart';
import '../theme_selection/theme_model.dart';

/// Collects exactly [kStripShotCount] booth stills for FotoFlashback compose.
class FotoFlashbackCaptureViewModel extends ChangeNotifier {
  FotoFlashbackCaptureViewModel({required this.theme});

  final ThemeModel theme;
  final List<XFile> _shots = <XFile>[];

  List<XFile> get shots => List<XFile>.unmodifiable(_shots);
  int get shotCount => _shots.length;
  bool get isComplete => _shots.length >= kStripShotCount;
  int get nextShotNumber => (_shots.length + 1).clamp(1, kStripShotCount);

  void addShot(PhotoModel photo) {
    if (isComplete) return;
    _shots.add(photo.imageFile);
    notifyListeners();
  }

  void removeLastShot() {
    if (_shots.isEmpty) return;
    _shots.removeLast();
    notifyListeners();
  }

  void clearShots() {
    if (_shots.isEmpty) return;
    _shots.clear();
    notifyListeners();
  }
}
