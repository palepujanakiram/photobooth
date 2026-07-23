import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted light/dark preference for staff screens only (guest kiosk unchanged).
class StaffThemeController extends ChangeNotifier {
  StaffThemeController({bool isDark = true}) : _isDark = isDark;

  static const prefsKey = 'staff_ui_dark_mode';

  bool _isDark;
  bool _loaded = false;

  bool get isDark => _isDark;
  bool get isLoaded => _loaded;

  /// Default dark matches the current staff dashboard aesthetic.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _isDark = prefs.getBool(prefsKey) ?? true;
    _loaded = true;
    notifyListeners();
  }

  Future<void> toggle() => setDark(!_isDark);

  Future<void> setDark(bool value) async {
    if (_isDark == value && _loaded) return;
    _isDark = value;
    _loaded = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKey, value);
  }
}
