// Web-specific Dio configuration
// This file is only imported on web platforms

import 'package:dio/dio.dart';
import 'package:dio/browser.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Configures Dio to use browser HTTP adapter on web
void configureDioForWeb(Dio dio) {
  if (kIsWeb) {
    try {
      dio.httpClientAdapter = BrowserHttpClientAdapter();
      print('✅ Configured Dio with BrowserHttpClientAdapter for web');
    } catch (e) {
      print('❌ Failed to configure BrowserHttpClientAdapter: $e');
      rethrow;
    }
  } else {
    print('ℹ️ Skipping browser adapter configuration (not on web)');
  }
}

