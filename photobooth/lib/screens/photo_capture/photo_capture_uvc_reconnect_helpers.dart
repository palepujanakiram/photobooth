import 'photo_capture_uvc_feed_phase.dart';

/// True when a USB disconnect event should not trigger auto-reconnect.
///
/// Intentional controller teardown (resume, recycle, idle sleep) often emits
/// transient `disconnected` events from the native USB monitor.
bool uvcShouldIgnoreDisconnectEvent({
  required DateTime? ignoreDisconnectUntil,
  required bool initializing,
  required bool openingController,
  required bool reconnectInFlight,
  required bool withinShutterGrace,
  required bool holdLiveFeedClosed,
  required UvcFeedPhase phase,
  DateTime? now,
}) {
  if (initializing || openingController || reconnectInFlight) return true;
  if (withinShutterGrace || holdLiveFeedClosed) return true;
  if (phase != UvcFeedPhase.live) return true;
  final until = ignoreDisconnectUntil;
  if (until == null) return false;
  return (now ?? DateTime.now()).isBefore(until);
}

/// Exponential backoff for auto-reconnect (650 ms → 10 s cap).
Duration uvcReconnectBackoffDelay(int attempt) {
  final capped = attempt.clamp(1, 8);
  final multiplier = 1 << (capped - 1);
  final ms = (650 * multiplier).clamp(650, 10000);
  return Duration(milliseconds: ms);
}

/// Whether another auto-reconnect attempt is allowed.
bool uvcMayScheduleAutoReconnect({
  required int attemptCount,
  required int maxAttempts,
}) {
  return attemptCount < maxAttempts;
}

/// Merges [extension] into [current] and returns the later instant.
DateTime? uvcLaterDisconnectIgnoreUntil({
  required DateTime? current,
  required Duration extension,
  DateTime? now,
}) {
  final candidate = (now ?? DateTime.now()).add(extension);
  if (current == null || candidate.isAfter(current)) {
    return candidate;
  }
  return current;
}
