import 'package:shared_preferences/shared_preferences.dart';

/// Local preference: alternate "stage preview" layout on the generate screen.
///
/// Default **false** (classic spinner / compact header). Opt-in for field testing;
/// effective only when [parallelImageCount] > 1 (SSE pipeline).
class GenerationDisplayPreferences {
  GenerationDisplayPreferences._();

  static const String _kProgressiveGenerationUi = 'progressive_generation_ui_v1';

  static Future<bool> getUseProgressiveGenerationUi() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kProgressiveGenerationUi) ?? false;
  }

  static Future<void> setUseProgressiveGenerationUi(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kProgressiveGenerationUi, value);
  }
}
