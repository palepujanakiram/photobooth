import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

import '../screens/photo_capture/photo_model.dart';
import '../services/api_service.dart';
import '../services/session_manager.dart';
import 'app_strings.dart';
import 'exceptions.dart';
import 'image_helper.dart';
import 'web_flow_trace.dart';

/// Result of ensuring the session row has a guest photo before payment/generation.
class SessionPhotoSyncOutcome {
  const SessionPhotoSyncOutcome({
    this.alreadyPresent = false,
    this.uploaded = false,
    this.errorMessage,
  });

  final bool alreadyPresent;
  final bool uploaded;
  final String? errorMessage;

  bool get isReady =>
      errorMessage == null && (alreadyPresent || uploaded);
}

/// True when GET `/api/sessions/:id` indicates a stored guest photo.
bool sessionResponseHasUserImage(Map<String, dynamic>? session) {
  if (session == null) return false;
  if (session['hasUserImage'] == true) return true;
  final preview = session['userImageUrl'];
  if (preview is String && preview.trim().isNotEmpty) return true;
  final compressed = session['compressedImageUrl'];
  if (compressed is String && compressed.trim().isNotEmpty) return true;
  return false;
}

/// Ensures [photo] is PATCHed to the session when the server has no image yet.
///
/// Generation and payment endpoints read `session.userImageUrl` from the DB;
/// the in-memory [PhotoModel] alone is not enough.
Future<SessionPhotoSyncOutcome> ensureSessionPhotoOnServer({
  required String sessionId,
  required PhotoModel photo,
  ApiService? apiService,
  SessionManager? sessionManager,
  @visibleForTesting Future<Map<String, dynamic>?> Function(String id)?
      fetchSessionFn,
  @visibleForTesting Future<String> Function(XFile file)? encodeForUploadFn,
  @visibleForTesting
  Future<Map<String, dynamic>> Function({
    required String sessionId,
    required String userImageUrl,
  })? patchPhotoFn,
}) async {
  final sid = sessionId.trim();
  if (sid.isEmpty) {
    return const SessionPhotoSyncOutcome(
      errorMessage: AppStrings.sessionPhotoSyncNoSession,
    );
  }

  final api = apiService ?? ApiService();
  final sm = sessionManager ?? SessionManager();
  final fetchSession = fetchSessionFn ?? api.fetchSession;
  final encodeForUpload = encodeForUploadFn ?? ImageHelper.encodeImageForUpload;
  final patchPhoto = patchPhotoFn ??
      (({required String sessionId, required String userImageUrl}) {
        return api.updateSession(
          sessionId: sessionId,
          userImageUrl: userImageUrl,
          framingMetadata: const <String, dynamic>{
            'applied': false,
            'mode': 'auto',
            'originalImageUrl': null,
          },
        );
      });

  try {
    final existing = await fetchSession(sid);
    if (sessionResponseHasUserImage(existing)) {
      return const SessionPhotoSyncOutcome(alreadyPresent: true);
    }

    WebFlowTrace.log('SESSION_PHOTO', 'sync_upload_start sessionId=${sid.length <= 8 ? sid : '${sid.substring(0, 8)}…'}');

    var imageFile = photo.imageFile;
    if (kIsWeb) {
      imageFile = await _materializeWebXFile(imageFile);
    }

    final dataUrl = await encodeForUpload(imageFile);
    final response = await patchPhoto(sessionId: sid, userImageUrl: dataUrl);
    sm.setSessionFromResponse(response);

    final verified = await fetchSession(sid);
    if (!sessionResponseHasUserImage(verified)) {
      return const SessionPhotoSyncOutcome(
        errorMessage: AppStrings.sessionPhotoSyncVerifyFailed,
      );
    }

    WebFlowTrace.log('SESSION_PHOTO', 'sync_upload_done');
    return const SessionPhotoSyncOutcome(uploaded: true);
  } on ApiException catch (e) {
    return SessionPhotoSyncOutcome(errorMessage: e.message);
  } catch (e) {
    return SessionPhotoSyncOutcome(
      errorMessage: '${AppStrings.sessionPhotoSyncFailed}: $e',
    );
  }
}

Future<XFile> _materializeWebXFile(XFile file) async {
  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) {
    throw ApiException(AppStrings.imageFileEmpty);
  }
  return XFile.fromData(
    bytes,
    name: 'session_sync_${DateTime.now().millisecondsSinceEpoch}.jpg',
    mimeType: 'image/jpeg',
  );
}
