// Web-specific Dio configuration
// This file is only imported on web platforms

import 'package:dio/dio.dart';
import 'package:dio/browser.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/logger.dart';

/// Configures Dio to use browser HTTP adapter on web
void configureDioForWeb(Dio dio) {
  if (kIsWeb) {
    try {
      dio.httpClientAdapter = BrowserHttpClientAdapter();
      AppLogger.debug('✅ Configured Dio with BrowserHttpClientAdapter for web');
    } catch (e, st) {
      AppLogger.error(
        'Failed to configure BrowserHttpClientAdapter',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  } else {
    AppLogger.debug('ℹ️ Skipping browser adapter configuration (not on web)');
  }
}

