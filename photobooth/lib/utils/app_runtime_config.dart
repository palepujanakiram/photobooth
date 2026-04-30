import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../models/app_settings_model.dart';

/// Runtime flags driven by [AppSettingsModel.showGenerationCommentary] from `/api/settings`.
///
/// Default is **off** until settings load. When `showGenerationCommentary == true`:
/// - "Low memory kiosk" optimizations ([AppConstants.kLowMemoryKioskMode])
/// - Verbose logging, API logging, loader debug lines, native camera info pane, etc.
class AppRuntimeConfig extends ChangeNotifier {
  AppRuntimeConfig._();
  static final AppRuntimeConfig instance = AppRuntimeConfig._();

  bool _showGenerationCommentary = false;

  /// Mirrors `/api/settings` → `showGenerationCommentary`. Drives all debug / kiosk-RAM behavior.
  bool get showGenerationCommentary => _showGenerationCommentary;

  void applyFromSettings(AppSettingsModel? settings) {
    final next = settings?.showGenerationCommentary == true;
    if (next == _showGenerationCommentary) return;
    _showGenerationCommentary = next;
    notifyListeners();
  }
}

/// Applies [PaintingBinding.instance.imageCache] limits from [AppRuntimeConfig.showGenerationCommentary].
/// Call after [WidgetsFlutterBinding.ensureInitialized] (defaults to **generous** limits until settings load).
void applyFlutterImageCacheLimits() {
  final low = AppRuntimeConfig.instance.showGenerationCommentary;
  final ic = PaintingBinding.instance.imageCache;
  if (low) {
    ic.maximumSize = 40;
    ic.maximumSizeBytes = 50 * 1024 * 1024;
  } else {
    ic.maximumSize = 100;
    ic.maximumSizeBytes = 100 * 1024 * 1024;
  }
}
