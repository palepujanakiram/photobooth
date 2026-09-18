import 'dart:typed_data';

import '../../../utils/event_bulk_import.dart';
import '../../../utils/exceptions.dart';
import '../../../utils/logger.dart';
import '../../api_service.dart';
import '../../kiosk_manager.dart';
import '../../session_manager.dart';
import 'event_capture_coordinator.dart';

/// How a phone/web capture lands when this runtime has no local event ledger.
class EventDeviceCaptureUploadHooks {
  const EventDeviceCaptureUploadHooks({
    required this.kioskCode,
    required this.createSession,
    required this.updateSession,
    this.rememberSession,
  });

  final Future<String?> Function() kioskCode;
  final Future<Map<String, dynamic>> Function(String? kioskCode) createSession;
  final Future<void> Function(String sessionId, String dataUrl) updateSession;
  final void Function(Map<String, dynamic> response)? rememberSession;
}

/// Uploads one still as an event-capture guest session (web / no SQLite).
class EventDeviceCaptureUploader {
  EventDeviceCaptureUploader({EventDeviceCaptureUploadHooks? hooks})
      : _hooks = hooks ?? EventDeviceCaptureUploader.productionHooks();

  final EventDeviceCaptureUploadHooks _hooks;

  static EventDeviceCaptureUploadHooks productionHooks() {
    final api = ApiService();
    final kiosk = KioskManager();
    final session = SessionManager();
    return EventDeviceCaptureUploadHooks(
      kioskCode: kiosk.getKioskCode,
      createSession: (code) => api.acceptTermsAndCreateSession(
        kioskCode: code,
        source: 'event-capture',
        groupConsentAccepted: true,
      ),
      updateSession: (id, url) => api.updateSession(
        sessionId: id,
        userImageUrl: url,
      ),
      rememberSession: session.setSessionFromResponse,
    );
  }

  Future<CaptureCommitOutcome> upload(Uint8List bytes, String fileName) async {
    if (bytes.isEmpty) {
      return const CaptureCommitOutcome(
        queued: false,
        message: 'The photo was not where the camera said',
      );
    }
    try {
      final code = await _hooks.kioskCode();
      final response = await _hooks.createSession(code);
      final sessionId = eventSessionIdFromCreateResponse(response);
      if (sessionId == null) {
        return const CaptureCommitOutcome(
          queued: false,
          message: 'Could not store the photo',
        );
      }
      _hooks.rememberSession?.call(response);
      final mime = eventImportMimeFromHint(null, fileName) ?? 'image/jpeg';
      await _hooks.updateSession(
        sessionId,
        eventImportBytesToDataUrl(bytes, mime),
      );
      return const CaptureCommitOutcome(
        queued: true,
        message: 'Added to queue',
      );
    } on ApiException catch (e) {
      return CaptureCommitOutcome(queued: false, message: e.message);
    } catch (e, st) {
      AppLogger.error('Device capture upload failed', error: e, stackTrace: st);
      return const CaptureCommitOutcome(
        queued: false,
        message: 'Could not queue the photo',
      );
    }
  }
}
