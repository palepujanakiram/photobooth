import '../utils/exceptions.dart';
import 'api_service.dart';
import 'customer_session_lifecycle.dart';
import 'file_helper.dart';
import 'session_manager.dart';

/// Server + local wipe when the customer chooses "Delete my photos".
class CustomerDataDeletion {
  CustomerDataDeletion({
    required SessionManager sessionManager,
    required Future<void> Function(String sessionId) deleteSessionOnServer,
  })  : _sessionManager = sessionManager,
        _deleteSessionOnServer = deleteSessionOnServer;

  factory CustomerDataDeletion.standard({
    required ApiService apiService,
    required SessionManager sessionManager,
  }) {
    return CustomerDataDeletion(
      sessionManager: sessionManager,
      deleteSessionOnServer: apiService.deleteSession,
    );
  }

  final SessionManager _sessionManager;
  final Future<void> Function(String sessionId) _deleteSessionOnServer;

  /// DELETE `/api/sessions/{id}` when possible, then clear kiosk customer state.
  Future<void> deleteMyPhotos() async {
    try {
      final sessionId = _sessionManager.sessionId;
      if (sessionId != null) {
        await _deleteSessionOnServer(sessionId);
      }
    } finally {
      await endPhotoboothCustomerSessionLogged('deleteMyPhotos');
      await FileHelper.cleanupTempImages();
    }
  }
}

/// User-facing error for [CustomerDataDeletion.deleteMyPhotos].
String deleteMyPhotosErrorMessage(Object error) {
  if (error is ApiException) return error.userFacingMessage;
  return 'Could not delete your photos. Please try again or ask staff for help.';
}
