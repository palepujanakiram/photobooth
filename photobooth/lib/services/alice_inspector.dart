import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_alice/alice.dart';

/// Holds the Alice HTTP inspector instance for debugging.
/// Initialized in [initialize] from main with the app's navigator key.
/// Only created in debug mode; [instance] is null in release.
class AliceInspector {
  AliceInspector._();

  static Alice? _instance;

  static Alice? get instance => _instance;

  /// Call from main after creating the navigator key. No-op in release.
  static void initialize(GlobalKey<NavigatorState> navigatorKey) {
    if (kDebugMode) {
      _instance = Alice(navigatorKey: navigatorKey);
    }
  }
}
