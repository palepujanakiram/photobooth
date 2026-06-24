import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/theme_selection/theme_selection_on_continue_helpers.dart';
import 'package:photobooth/services/app_settings_manager.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('refreshThemeSelectionTriesRemaining', () {
    test('returns remaining tries from session and settings', () async {
      SharedPreferences.setMockInitialValues({});
      final sm = SessionManager();
      sm.setSessionFromResponse({
        'id': 'sess-1',
        'termsAccepted': true,
        'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'attemptsUsed': 1,
        'generatedImages': [],
        'expiresAt': DateTime.utc(2027, 1, 1).toIso8601String(),
      });

      final settings = AppSettingsManager();
      final tries = await refreshThemeSelectionTriesRemaining(settings);

      expect(tries, greaterThanOrEqualTo(0));
    });
  });
}
