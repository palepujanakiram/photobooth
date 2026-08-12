import '../screens/theme_selection/theme_model.dart';
import 'capture_session_kind.dart';
import 'classic_shot_mode.dart';
import 'logger.dart';

/// Optional backup of the active Classic theme for TV remounts.
///
/// Mode itself lives on [PhotoCaptureScreen.sessionKind] (constructor).
/// This only stores the strip [ThemeModel] so a remounted Classic State can
/// recover the theme if route args were dropped.
///
/// Never consulted by FotoZen POSE screens.
class ClassicCaptureIntent {
  ClassicCaptureIntent._();

  static CaptureSessionKind? _kind;
  static ThemeModel? _theme;

  static void beginClassic({
    required ClassicShotMode mode,
    required ThemeModel theme,
  }) {
    _kind = CaptureSessionKindX.fromClassicShotMode(mode);
    _theme = theme;
    AppLogger.debug(
      'ClassicCaptureIntent.beginClassic kind=$_kind theme=${theme.id}',
    );
  }

  static CaptureSessionKind? peekKind() => _kind;

  static ThemeModel? peekTheme() => _theme;

  static void clear() {
    if (_kind != null) {
      AppLogger.debug('ClassicCaptureIntent.clear wasKind=$_kind');
    }
    _kind = null;
    _theme = null;
  }

  /// Test-only.
  static void resetForTests() {
    clear();
    // Keep private constructor exercised for coverage.
    ClassicCaptureIntent._();
  }
}
