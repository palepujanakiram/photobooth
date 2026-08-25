import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/api_environment.dart';
import '../utils/app_config.dart';
import '../utils/logger.dart';

/// Persists Stage vs Live API host across restarts.
///
/// Load once in [main] before any [ApiService] / Dio is created. Splash manage
/// can change the selection; [AppConfig.baseUrl] then reflects the new host for
/// newly constructed clients (and rebound managers).
class ApiEnvironmentStore {
  ApiEnvironmentStore._();

  static const String prefsKey = 'api_environment';

  static ApiEnvironment? _override;
  static bool _loaded = false;

  /// True after [load] has run (prefs may still be empty).
  static bool get isLoaded => _loaded;

  /// Explicit Stage/Live when set; otherwise [AppConfig] falls back to
  /// dart-define / branch default.
  static ApiEnvironment? get override => _override;

  static ApiEnvironment get current {
    return _override ?? AppConfig.branchDefaultEnvironment;
  }

  static String get currentBaseUrl => current.baseUrl;

  /// Reads SharedPreferences into memory. Safe to call more than once.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final parsed = apiEnvironmentFromStorage(prefs.getString(prefsKey));
      _override = parsed;
      _loaded = true;
      AppLogger.info(
        'API environment: ${current.label} (${current.baseUrl})'
        '${parsed == null ? ' [branch default]' : ''}',
      );
    } catch (e, st) {
      _loaded = true;
      AppLogger.warning(
        'API environment load failed; using branch default',
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
  }
}
