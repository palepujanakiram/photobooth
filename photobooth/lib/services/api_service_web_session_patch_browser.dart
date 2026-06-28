import 'dart:async';
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import '../utils/app_config.dart';
import '../utils/constants.dart';
import '../utils/exceptions.dart';
import '../utils/web_flow_trace.dart';
import 'client_identification.dart';
import 'kiosk_session_auth.dart';
import 'session_manager.dart';

/// PATCH session photo on **web** via `XMLHttpRequest` (abortable timeout).
Future<String> patchSessionPhotoBodyOnWeb({
  required String sessionId,
  required String jsonBody,
  Duration timeout = AppConstants.kSessionUploadTimeout,
  SessionManager? sessionManager,
  Object? client,
}) async {
  final uri = '${AppConstants.kBaseUrl}/api/sessions/$sessionId';
  final headers = ClientIdentification.mergeHeaders({
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    ...AppConfig.authorizationBearerHeader,
  }).map((key, value) => MapEntry(key, value.toString()));
  final kioskToken = (sessionManager ?? SessionManager()).kioskAuthToken;
  if (kioskToken != null && kioskToken.isNotEmpty) {
    headers[kKioskSessionTokenHeader] = kioskToken;
  }

  WebFlowTrace.log('PATCH_HTTP', 'xhr_open uri=$uri bytes=${jsonBody.length}');

  final xhr = html.HttpRequest();
  final completer = Completer<String>();
  late final Timer abortTimer;

  void finishError(Object error) {
    if (!completer.isCompleted) completer.completeError(error);
  }

  abortTimer = Timer(timeout, () {
    WebFlowTrace.log(
      'PATCH_HTTP',
      'xhr_timeout_abort after ${timeout.inSeconds}s',
    );
    xhr.abort();
    finishError(
      TimeoutException(
        'Photo upload timed out after ${timeout.inSeconds} seconds.',
      ),
    );
  });

  xhr.onLoad.listen((_) {
    abortTimer.cancel();
    final status = xhr.status ?? 0;
    WebFlowTrace.log(
      'PATCH_HTTP',
      'xhr_onLoad status=$status respChars=${xhr.responseText?.length ?? 0}',
    );
    if (status >= 200 && status < 300) {
      completer.complete(xhr.responseText ?? '');
      return;
    }
    finishError(
      ApiException(_sessionPatchFailureMessage(status, xhr.responseText), status),
    );
  });

  xhr.onError.listen((_) {
    abortTimer.cancel();
    WebFlowTrace.log('PATCH_HTTP', 'xhr_onError');
    finishError(
      ApiException('Network error during photo upload.'),
    );
  });

  xhr.onAbort.listen((_) {
    abortTimer.cancel();
    WebFlowTrace.log('PATCH_HTTP', 'xhr_onAbort');
    if (!completer.isCompleted) {
      finishError(
        ApiException('Photo upload was cancelled or timed out.'),
      );
    }
  });

  xhr.open('PATCH', uri);
  headers.forEach(xhr.setRequestHeader);
  WebFlowTrace.log('PATCH_HTTP', 'xhr_send');
  xhr.send(jsonBody);

  return completer.future;
}

String _sessionPatchFailureMessage(int status, String? responseText) {
  final body = responseText?.trim();
  if (body != null && body.isNotEmpty) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final err = decoded['error'] ?? decoded['message'];
        if (err is String && err.trim().isNotEmpty) {
          return 'Upload failed (HTTP $status): ${err.trim()}';
        }
      }
    } on FormatException {
      // Fall through to generic message.
    }
  }
  return 'Upload failed (HTTP $status)';
}
