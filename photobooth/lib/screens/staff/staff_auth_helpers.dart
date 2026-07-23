import '../../utils/exceptions.dart';

/// Shared staff auth failure detection (dashboard, payments, login).
abstract final class StaffAuthHelpers {
  /// True when the API rejected the staff session (missing/invalid/expired).
  static bool isAuthFailure(ApiException e) {
    if (e.statusCode == 401) return true;
    final m = e.message.toLowerCase();
    return m.contains('unauthorized') ||
        m.contains('expired') ||
        m.contains('log in');
  }
}
