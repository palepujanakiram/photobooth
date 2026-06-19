import 'package:flutter/foundation.dart' show ChangeNotifier, kIsWeb;
import 'package:flutter/painting.dart';

import '../models/app_settings_model.dart';

/// Runtime flags driven by [AppSettingsModel.showGenerationCommentary] from `/api/settings`.
///
/// Default is **off** until settings load. When `showGenerationCommentary == true`:
/// - **Native:** "Low memory kiosk" optimizations ([AppConstants.kLowMemoryKioskMode])
/// - **Web:** on-screen Logs / Perf trace / JS-heap HUD and loader debug lines.
/// - On-screen debug HUD (Logs, Perf trace, RAM or JS heap), API logging when
///   [AppConstants.kEnableLogOutput], loader debug lines, native camera info pane (non-web).
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
///
/// **Web:** always generous — low limits after settings load would evict capture previews mid-upload.
void applyFlutterImageCacheLimits() {
  final ic = PaintingBinding.instance.imageCache;
  if (kIsWeb) {
    ic.maximumSize = 100;
    ic.maximumSizeBytes = 100 * 1024 * 1024;
    return;
  }
  final low = AppRuntimeConfig.instance.showGenerationCommentary;
  if (low) {
    ic.maximumSize = 40;
    ic.maximumSizeBytes = 50 * 1024 * 1024;
  } else {
    ic.maximumSize = 100;
    ic.maximumSizeBytes = 100 * 1024 * 1024;
  }
}
