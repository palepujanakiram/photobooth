import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_alice/alice.dart';

import '../utils/app_runtime_config.dart';

/// Forwards to Alice only when `kDebugMode` and `/api/settings` → `showGenerationCommentary`.
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
    if (!kDebugMode) return null;
    if (!AppRuntimeConfig.instance.showGenerationCommentary) return null;
    final alice = AliceInspector.instance;
    if (alice == null) return null;
    return alice.getDioInterceptor();
  }
}

/// Holds the Alice HTTP inspector for debugging.
/// [instance] is non-null only in debug builds when `showGenerationCommentary` is true
/// (after [syncWithRuntimeConfig] runs).
class AliceInspector {
  AliceInspector._();

  static GlobalKey<NavigatorState>? _navigatorKey;
  static Alice? _instance;

  static Alice? get instance => _instance;

  /// Stores the navigator key and applies [syncWithRuntimeConfig]. Call from [main].
  static void initialize(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    syncWithRuntimeConfig();
  }

  /// Recreate [instance] when `/api/settings` changes. Safe to call from build (e.g. [Consumer]).
  static void syncWithRuntimeConfig() {
    if (!kDebugMode) {
      _instance = null;
      return;
    }
    final want = AppRuntimeConfig.instance.showGenerationCommentary;
    if (want && _navigatorKey != null) {
      _instance ??= Alice(navigatorKey: _navigatorKey!);
    } else {
      _instance = null;
    }
  }
}
