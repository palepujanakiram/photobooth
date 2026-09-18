import 'package:flutter/foundation.dart' show ChangeNotifier, kIsWeb;
import 'package:flutter/painting.dart';

import '../models/app_settings_model.dart';
import 'classic_pose_countdown.dart';
import 'constants.dart';

/// Runtime flags driven by `/api/settings` ([AppSettingsModel]).
///
/// Default is **off** until settings load. When `showGenerationCommentary == true`:
/// - **Native:** "Low memory kiosk" optimizations ([AppConstants.kLowMemoryKioskMode])
/// - **Web:** on-screen Logs / Perf trace / JS-heap HUD and loader debug lines.
///
/// [showApiLogs] defaults to **on** even before settings load (and when the
/// API omits the key). When false, the Alice HTTP inspector icon is hidden
/// (debug and release native; always hidden on web).
///
/// When `thermalSafeMode == true`: UVC idle feed sleep and lifecycle pause on capture.
class AppRuntimeConfig extends ChangeNotifier {
  AppRuntimeConfig._();
  static final AppRuntimeConfig instance = AppRuntimeConfig._();

  bool _showGenerationCommentary = false;
  bool _showApiLogs = true;
  bool _thermalSafeMode = false;
  bool _injectClassicAfMarkers = false;
  int _classicPoseCountdownSeconds =
      AppConstants.kFlashbackCaptureCountdownSeconds;

  /// Mirrors `/api/settings` → `showGenerationCommentary`. Drives debug / kiosk-RAM behavior.
  bool get showGenerationCommentary => _showGenerationCommentary;

  /// Mirrors `/api/settings` → `show_api_logs`. Drives the Alice inspector icon.
  /// True when settings have not loaded or the key is omitted.
  bool get showApiLogs => _showApiLogs;

  /// Mirrors `/api/settings` → `thermalSafeMode`. Drives UVC thermal relief on capture.
  bool get thermalSafeMode => _thermalSafeMode;

  /// Test-only: burn AF brackets into Classic captures (`photoStripConfig.injectAfMarkers`).
  bool get injectClassicAfMarkers => _injectClassicAfMarkers;

  /// Per-kiosk Classic pose countdown (5–15s). AI capture stays at 5s.
  int get classicPoseCountdownSeconds => _classicPoseCountdownSeconds;

  /// Apply Classic pose seconds from kiosk bind when `/api/settings` omits the key.
  void applyClassicPoseCountdown(int? raw) {
    final next = normalizeClassicPoseCountdownSeconds(raw);
    if (next == _classicPoseCountdownSeconds) return;
    _classicPoseCountdownSeconds = next;
    notifyListeners();
  }

  void applyFromSettings(AppSettingsModel? settings) {
    final nextCommentary = settings?.showGenerationCommentary == true;
    final nextShowApiLogs = settings?.showApiLogs ?? true;
    final nextThermal = settings?.thermalSafeMode == true;
    final nextInject = settings?.injectAfMarkers == true;
    final nextCountdown = settings == null
        ? AppConstants.kFlashbackCaptureCountdownSeconds
        : (settings.classicPoseCountdownSeconds != null
            ? normalizeClassicPoseCountdownSeconds(
                settings.classicPoseCountdownSeconds,
              )
            : _classicPoseCountdownSeconds);
    if (nextCommentary == _showGenerationCommentary &&
        nextShowApiLogs == _showApiLogs &&
        nextThermal == _thermalSafeMode &&
        nextInject == _injectClassicAfMarkers &&
        nextCountdown == _classicPoseCountdownSeconds) {
      return;
    }
    _showGenerationCommentary = nextCommentary;
    _showApiLogs = nextShowApiLogs;
    _thermalSafeMode = nextThermal;
    _injectClassicAfMarkers = nextInject;
    _classicPoseCountdownSeconds = nextCountdown;
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
