import 'package:alice/alice.dart';
import 'package:flutter/material.dart';

/// Global Alice instance for network inspection
/// Alice is an HTTP inspector tool that shows all API calls in the app UI
/// 
/// Usage:
/// - Shake device to open inspector
/// - Or call AliceInspector.show(context) programmatically
class AliceInspector {
  static Alice? _instance;
  static final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  
  /// Get or create Alice instance
  static Alice get instance {
    if (_instance == null) {
      _instance = Alice();
      _instance!.setNavigatorKey(_navigatorKey);
    }
    return _instance!;
  }
  
  /// Show Alice inspector UI
  static void show(BuildContext context) {
    instance.showInspector();
  }
  
  /// Get Alice navigator key for app integration
  static GlobalKey<NavigatorState> get navigatorKey => _navigatorKey;
}
