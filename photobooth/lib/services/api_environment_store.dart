import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/api_environment.dart';
import '../utils/app_config.dart';
import '../utils/logger.dart';

/// Persists Stage vs Live API host for the current process.
///
/// Load once in [main] before any [ApiService] / Dio is created. Splash manage
/// can still switch hosts via [set] for debugging; [load] always cold-starts on
/// Live (or the compile-time [AppConfig.dartDefineBaseUrl]) so booths cannot
/// stay stuck on Stage — production kiosk codes such as AAA exist only on Live.
class ApiEnvironmentStore {
  ApiEnvironmentStore._();

  /// Unused in production; exists so unit tests can construct the store.
  @visibleForTesting
  static ApiEnvironmentStore createForTests() => ApiEnvironmentStore._();

  static const String prefsKey = 'api_environment';

  static ApiEnvironment? _override;
  static bool _loaded = false;

  /// Null in production — [load] uses [SharedPreferences.getInstance].
  @visibleForTesting
  static Future<SharedPreferences> Function()? debugLoadPrefs;

  /// True after [load] has run (prefs may still be empty).
  static bool get isLoaded => _loaded;

  /// Explicit Stage/Live when set; otherwise [AppConfig] falls back to
  /// dart-define / branch default.
  static ApiEnvironment? get override => _override;

  static ApiEnvironment get current {
    return _override ?? AppConfig.branchDefaultEnvironment;
  }

  static String get currentBaseUrl => current.baseUrl;

  /// Reads SharedPreferences, then asserts Live (or dart-define) for cold start.
  static Future<void> load() async {
    try {
      final prefs = await (debugLoadPrefs ?? SharedPreferences.getInstance)();
      final define = AppConfig.effectiveDartDefineBaseUrl;
      if (define.isNotEmpty) {
        // Web / CI builds: same-origin or explicit BASE_URL wins. Drop a stale
        // Stage preference that would bypass the proxy and 404 real kiosks.
        _override = null;
        await prefs.remove(prefsKey);
        _loaded = true;
        AppLogger.info(
          'API environment: dart-define BASE_URL=$define '
          '(cleared Stage/Live prefs for cold start)',
        );
        return;
      }

      // Native booths: always cold-start on Live. Stage remains available via
      // splash manage [set] until the next process restart.
      _override = ApiEnvironment.live;
      await prefs.setString(
        prefsKey,
        apiEnvironmentStorageValue(ApiEnvironment.live),
      );
      _loaded = true;
      AppLogger.info(
        'API environment: ${current.label} (${current.baseUrl}) [cold-start live]',
      );
    } catch (e, st) {
      _override = ApiEnvironment.live;
      _loaded = true;
      AppLogger.warning(
        'API environment load failed; using Live',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Persists [env] and updates the in-memory override immediately.
  static Future<void> set(ApiEnvironment env) async {
    _override = env;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, apiEnvironmentStorageValue(env));
    AppLogger.info('API environment saved: ${env.label} (${env.baseUrl})');
  }

  @visibleForTesting
  static void resetForTests({ApiEnvironment? override}) {
    _override = override;
    _loaded = override != null;
    debugLoadPrefs = null;
  }
}
