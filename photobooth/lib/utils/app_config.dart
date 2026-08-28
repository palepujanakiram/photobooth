import 'package:flutter/foundation.dart' show visibleForTesting;

import '../services/api_environment_store.dart';
import 'api_environment.dart';

/// Application Configuration
///
/// This file contains configurable API base URL and related endpoints.
/// In-app links (e.g. Terms URL) live in [AppConstants].
/// Modify these values to change the app's endpoints without code changes.
class AppConfig {
  // API Configuration
  /// Compile-time override: `--dart-define=BASE_URL=https://…`
  ///
  /// When empty, [baseUrl] uses the splash Stage/Live preference (or the
  /// default [branchDefaultEnvironment]).
  static const String dartDefineBaseUrl = String.fromEnvironment('BASE_URL');

  /// Test-only stand-in for [dartDefineBaseUrl] (const fromEnvironment is empty
  /// in VM unit tests). Null in production — [effectiveDartDefineBaseUrl]
  /// then uses dart-define.
  @visibleForTesting
  static String? dartDefineBaseUrlOverrideForTests;

  /// Trimmed `--dart-define=BASE_URL` value used by [baseUrl] and splash load.
  ///
  /// Production: same as [dartDefineBaseUrl].trim(). Tests may set
  /// [dartDefineBaseUrlOverrideForTests].
  static String get effectiveDartDefineBaseUrl =>
      (dartDefineBaseUrlOverrideForTests ?? dartDefineBaseUrl).trim();

  /// Default when prefs and dart-define are unset — production Live API.
  static const ApiEnvironment branchDefaultEnvironment = ApiEnvironment.live;

  /// Const host for Retrofit `@RestApi` codegen only — runtime Dio uses [baseUrl].
  static const String retrofitAnnotationBaseUrl = 'https://fotozenai.fly.dev';

  /// Effective API base URL (no trailing slash).
  ///
  /// Priority: splash prefs → `--dart-define=BASE_URL` → [branchDefaultEnvironment].
  static String get baseUrl {
    final fromPrefs = ApiEnvironmentStore.override?.baseUrl;
    if (fromPrefs != null && fromPrefs.isNotEmpty) {
      return _stripTrailingSlash(fromPrefs);
    }
    final fromDefine = effectiveDartDefineBaseUrl;
    if (fromDefine.isNotEmpty) {
      return _stripTrailingSlash(fromDefine);
    }
    return branchDefaultEnvironment.baseUrl;
  }

  static String _stripTrailingSlash(String url) {
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// Short guest-facing URL used by the booth QR.
  static String shareUrlForToken(String token) =>
      '$baseUrl/s/${Uri.encodeComponent(token.trim())}';

  /// Long fallback URL shown below the booth QR.
  static String shareLongUrlForToken(String token) =>
      '$baseUrl/share/${Uri.encodeComponent(token.trim())}';

  /// JWT for `Authorization: Bearer …` on API calls (e.g. Supabase anon / edge gateway).
  ///
  /// **Public credential** — enforce authorization on the server (RLS, session checks,
  /// rate limits). Do not commit production tokens; pass at build time:
  /// `--dart-define=API_BEARER_TOKEN=<jwt>`.
  ///
  /// Local/dev: export the Supabase **anon** role JWT via dart-define or CI secret.
  static const String apiBearerToken = String.fromEnvironment(
    'API_BEARER_TOKEN',
    defaultValue: '',
  );

  static Map<String, String> get authorizationBearerHeader =>
      bearerHeaderForToken(apiBearerToken);

  /// Builds the API bearer header for [token] (empty map when blank).
  @visibleForTesting
  static Map<String, String> bearerHeaderForToken(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) return const {};
    return {'Authorization': 'Bearer $trimmed'};
  }

  /// Bugsnag API key for release/profile mobile builds (see [main.dart]).
  ///
  /// Set in `photobooth/.env` as `BUGSNAG_API_KEY=…`; release builds pick it up
  /// via `scripts/flutter_with_version.sh` (`--dart-define=BUGSNAG_API_KEY=…`).
  static const String bugsnagApiKey = String.fromEnvironment('BUGSNAG_API_KEY');

  /// Optional override for DNP print routing: `auto`, `usb`, or `wifi`.
  ///
  /// When unset, booth `/api/settings` `printerTransport` applies (default `auto`).
  static const String printerTransportOverride = String.fromEnvironment(
    'PRINTER_TRANSPORT',
    defaultValue: '',
  );
}
