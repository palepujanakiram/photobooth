import 'package:flutter/foundation.dart' show ChangeNotifier, kIsWeb;
import 'package:flutter/painting.dart';

import '../models/app_settings_model.dart';

/// Runtime flags driven by `/api/settings` ([AppSettingsModel]).
///
/// Default is **off** until settings load. When `showGenerationCommentary == true`:
/// - **Native:** "Low memory kiosk" optimizations ([AppConstants.kLowMemoryKioskMode])
/// - **Web:** on-screen Logs / Perf trace / JS-heap HUD and loader debug lines.
///
/// When `thermalSafeMode == true`: UVC idle feed sleep and lifecycle pause on capture.
class AppRuntimeConfig extends ChangeNotifier {
  AppRuntimeConfig._();
  static final AppRuntimeConfig instance = AppRuntimeConfig._();

  bool _showGenerationCommentary = false;
  bool _thermalSafeMode = false;

  /// Mirrors `/api/settings` → `showGenerationCommentary`. Drives debug / kiosk-RAM behavior.
  bool get showGenerationCommentary => _showGenerationCommentary;

  /// Mirrors `/api/settings` → `thermalSafeMode`. Drives UVC thermal relief on capture.
  bool get thermalSafeMode => _thermalSafeMode;

  void applyFromSettings(AppSettingsModel? settings) {
    final nextCommentary = settings?.showGenerationCommentary == true;
    final nextThermal = settings?.thermalSafeMode == true;
    if (nextCommentary == _showGenerationCommentary &&
        nextThermal == _thermalSafeMode) {
      return;
    }
    _showGenerationCommentary = nextCommentary;
    _thermalSafeMode = nextThermal;
    notifyListeners();
  }
}

/// Applies [PaintingBinding.instance.imageCache] limits from [AppRuntimeConfig.showGenerationCommentary].
/// Call after [WidgetsFlutterBinding.ensureInitialized] (defaults to **generous** limits until settings load).
///
/// **Web:** always generous — low limits after settings load would evict capture previews mid-upload.
void applyFlutterImageCacheLimits() {
  final ic = PaintingBinding.instance.imageCache;
  if (kIsWeb) {
    ic.maximumSize = 100;
    ic.maximumSizeBytes = 100 * 1024 * 1024;
    return;
  }
  final low = AppRuntimeConfig.instance.showGenerationCommentary ||
      AppRuntimeConfig.instance.thermalSafeMode;
  if (low) {
    ic.maximumSize = 40;
    ic.maximumSizeBytes = 50 * 1024 * 1024;
  } else {
    ic.maximumSize = 100;
    ic.maximumSizeBytes = 100 * 1024 * 1024;
  }
}
