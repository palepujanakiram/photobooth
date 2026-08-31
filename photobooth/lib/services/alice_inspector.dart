import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_alice/alice.dart';

import '../utils/app_runtime_config.dart';

/// Forwards to Alice only when [AliceInspector.isRequested] (debug native).
/// **Web:** always a no-op — Alice relies on overlays/navigator patterns that are fragile on web.
/// Safe to add on every Dio instance: no-ops until those conditions are true.
class AliceDioProxyInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final inner = _delegate();
    if (inner != null) {
      inner.onRequest(options, handler);
    } else {
      handler.next(options);
    }
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final inner = _delegate();
    if (inner != null) {
      inner.onResponse(response, handler);
    } else {
      handler.next(response);
    }
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final inner = _delegate();
    if (inner != null) {
      inner.onError(err, handler);
    } else {
      handler.next(err);
    }
  }

  Interceptor? _delegate() {
    if (!AliceInspector.isRequested) return null;
    final alice = AliceInspector.instance;
    if (alice == null) return null;
    return alice.getDioInterceptor();
  }
}

/// Holds the Alice HTTP inspector for debugging.
/// [instance] is non-null only when [isRequested] (after [syncWithRuntimeConfig]).
/// **Always null on web and in release/profile builds.**
class AliceInspector {
  AliceInspector._();

  static GlobalKey<NavigatorState>? _navigatorKey;
  static Alice? _instance;

  static Alice? get instance => _instance;

  static GlobalKey<NavigatorState>? get navigatorKey => _navigatorKey;

  /// `--dart-define=ENABLE_ALICE=true` turns Alice on without `/api/settings`.
  static const String _enableAliceDefine = String.fromEnvironment('ENABLE_ALICE');

  /// Debug native + (`showApiLogs` **or** `ENABLE_ALICE=true`).
  /// [showApiLogs] defaults to true when `/api/settings` omits `show_api_logs`.
  static bool get isRequested {
    if (!kDebugMode || kIsWeb) return false;
    if (_enableAliceDefine == 'true') return true;
    return AppRuntimeConfig.instance.showApiLogs;
  }

  /// Stores the navigator key and applies [syncWithRuntimeConfig]. Call from [main].
  static void initialize(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    syncWithRuntimeConfig();
  }

  /// Recreate [instance] when `/api/settings` changes. Safe to call from build (e.g. [Consumer]).
  static void syncWithRuntimeConfig() {
    if (isRequested && _navigatorKey != null) {
      _instance ??= Alice(
        navigatorKey: _navigatorKey!,
        showNotification: false,
      );
    } else {
      _instance = null;
    }
  }
}
