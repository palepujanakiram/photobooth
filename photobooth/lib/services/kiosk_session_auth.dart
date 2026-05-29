import 'package:dio/dio.dart';

import 'session_manager.dart';

/// Header required by the API for kiosk-bound session routes after creation.
const String kKioskSessionTokenHeader = 'X-Kiosk-Session-Token';

/// JSON field on POST/PATCH session responses.
const String kKioskAuthTokenJsonKey = 'kioskAuthToken';

/// Reads the kiosk session token from a session API response body.
///
/// The backend has evolved field names over time; accept a few aliases to avoid
/// breaking older/newer deployments.
String? parseKioskAuthToken(Map<String, dynamic> json) {
  for (final key in <String>[
    kKioskAuthTokenJsonKey,
    'kioskSessionToken',
    'kioskSessionAuthToken',
    'kioskToken',
    'sessionToken',
  ]) {
    final v = json[key];
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  return null;
}

bool _isPublicApiPath(String path) {
  final p = path.split('?').first;
  if (!p.startsWith('/api/')) return true;

  // Session creation is unauthenticated; the response provides kioskAuthToken.
  if (p == '/api/sessions/accept-terms') return true;

  // App bootstrap content is public.
  if (p == '/api/themes') return true;
  if (p == '/api/settings') return true;

  // Kiosk-owned resources are guarded server-side; they require the session token.
  return false;
}

/// Whether this request path must include [kKioskSessionTokenHeader].
///
/// We attach the header broadly for all `/api/*` requests (except a small public
/// allowlist). This avoids missed coverage on new endpoints like
/// `/api/generation-runs/:id`.
bool requestNeedsKioskSessionToken(String path) {
  final p = path.split('?').first;
  if (!p.startsWith('/api/')) return false;
  return !_isPublicApiPath(p);
}

/// Attaches [kKioskSessionTokenHeader] from [SessionManager] on protected routes.
class KioskSessionTokenInterceptor extends Interceptor {
  KioskSessionTokenInterceptor({SessionManager? sessionManager})
      : _sessionManager = sessionManager ?? SessionManager();

  final SessionManager _sessionManager;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!requestNeedsKioskSessionToken(options.uri.path)) {
      handler.next(options);
      return;
    }
    final token = _sessionManager.kioskAuthToken;
    if (token != null && token.isNotEmpty) {
      options.headers[kKioskSessionTokenHeader] = token;
    }
    handler.next(options);
  }
}

void addKioskSessionTokenInterceptor(Dio dio, {SessionManager? sessionManager}) {
  dio.interceptors.add(
    KioskSessionTokenInterceptor(sessionManager: sessionManager),
  );
}
