import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_alice/alice.dart';

import '../utils/app_runtime_config.dart';
import 'api_logging_interceptor.dart';

/// Console request logs stay debug-only. Alice is attached in debug **and**
/// release (the proxy no-ops when [AliceInspector.isRequested] is false).
void addHttpInspectorInterceptors(Dio dio) {
  if (kDebugMode) {
    dio.interceptors.add(ApiLoggingInterceptor());
  }
  dio.interceptors.add(AliceDioProxyInterceptor());
}

/// Forwards to Alice only when [AliceInspector.isRequested] (native).
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

  Interceptor? _delegate() => AliceInspector.dioInterceptor;
}

/// Holds the Alice HTTP inspector.
/// [instance] is non-null only when [isRequested] (after [syncWithRuntimeConfig]).
/// **Always null on web.** Native debug, profile, and release follow `show_api_logs`.
class AliceInspector {
  AliceInspector._();

  static GlobalKey<NavigatorState>? _navigatorKey;
  static Alice? _instance;
  static Interceptor? _cachedDioInterceptor;

  static Alice? get instance => _instance;

  static GlobalKey<NavigatorState>? get navigatorKey => _navigatorKey;

  /// Shared Dio interceptor so request/response pair on the same [AliceCore].
  static Interceptor? get dioInterceptor {
    if (!isRequested) return null;
    final alice = _instance;
    if (alice == null) return null;
    return _cachedDioInterceptor ??= alice.getDioInterceptor();
  }

  /// `--dart-define=ENABLE_ALICE=true` turns Alice on even when `show_api_logs` is false.
  static const String _enableAliceDefine = String.fromEnvironment('ENABLE_ALICE');

  /// Native + (`showApiLogs` **or** `ENABLE_ALICE=true`). Off on web.
  /// [showApiLogs] defaults to true when `/api/settings` omits `show_api_logs`.
  static bool get isRequested => resolveIsRequested(
        isWeb: kIsWeb,
        showApiLogs: AppRuntimeConfig.instance.showApiLogs,
        enableAliceDefine: _enableAliceDefine,
      );

  /// Gate used by [isRequested]. Extracted so tests can cover web / dart-define
  /// without compile-time [kIsWeb] or `--dart-define`.
  @visibleForTesting
  static bool resolveIsRequested({
    required bool isWeb,
    required bool showApiLogs,
    required String enableAliceDefine,
  }) {
    if (isWeb) return false;
    if (enableAliceDefine == 'true') return true;
    return showApiLogs;
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
      _cachedDioInterceptor = null;
    }
  }

  @visibleForTesting
  static void resetForTests() {
    _instance = null;
    _navigatorKey = null;
    _cachedDioInterceptor = null;
  }
}
