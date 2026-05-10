import 'package:shared_preferences/shared_preferences.dart';

/// Local preference: "stage preview" (progressive / filmstrip) layout on generate.
///
/// Default **on** for new installs. Stored value overrides when set.
/// The full filmstrip + per-stage thumbnails only apply when
/// `/api/settings` `parallelImageCount` > 1 (SSE parallel generation).
class GenerationDisplayPreferences {
  GenerationDisplayPreferences._();

  static const String _kProgressiveGenerationUi = 'progressive_generation_ui_v1';

  static Future<bool> getUseProgressiveGenerationUi() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kProgressiveGenerationUi) ?? true;
  }

  static Future<void> setUseProgressiveGenerationUi(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kProgressiveGenerationUi, value);
  }
}
