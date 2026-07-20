import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

import 'app_config.dart';
import 'exceptions.dart';

/// Extra guidance appended to capture-screen upload errors on Flutter web.
String webUploadErrorHint({ApiException? apiError}) {
  return webUploadErrorHintImpl(
    isWeb: kIsWeb,
    baseUrl: AppConfig.baseUrl,
    apiError: apiError,
  );
}

/// Platform-aware body for [webUploadErrorHint] (unit-testable on the VM).
@visibleForTesting
String webUploadErrorHintImpl({
  required bool isWeb,
  required String baseUrl,
  ApiException? apiError,
}) {
  if (!isWeb) return '';

  final host = Uri.tryParse(baseUrl)?.host.toLowerCase() ?? '';
  final isLocalDev =
      host == 'localhost' || host == '127.0.0.1' || host.endsWith('.localhost');

  if (isLocalDev) {
    return '\n\nOn localhost web, run ./run_web_dev.sh (API proxy).';
  }

  if (apiError?.statusCode == 403) {
    return '\n\nYour kiosk session may have expired. Go back to Terms and start again.';
  }

  return '';
}
