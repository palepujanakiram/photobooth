import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_uvc_feed_phase.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_uvc_reconnect_helpers.dart';

void main() {
  final now = DateTime(2026, 7, 3, 10, 0);

  test('uvcShouldIgnoreDisconnectEvent during intentional transitions', () {
    expect(
      uvcShouldIgnoreDisconnectEvent(
        ignoreDisconnectUntil: null,
        initializing: true,
        openingController: false,
        reconnectInFlight: false,
        withinShutterGrace: false,
        holdLiveFeedClosed: false,
        phase: UvcFeedPhase.live,
        now: now,
      ),
      isTrue,
    );
    expect(
      uvcShouldIgnoreDisconnectEvent(
        ignoreDisconnectUntil: null,
        initializing: false,
        openingController: false,
        reconnectInFlight: true,
        withinShutterGrace: false,
        holdLiveFeedClosed: false,
        phase: UvcFeedPhase.live,
        now: now,
      ),
      isTrue,
    );
    expect(
      uvcShouldIgnoreDisconnectEvent(
        ignoreDisconnectUntil: now.add(const Duration(seconds: 2)),
        initializing: false,
        openingController: false,
        reconnectInFlight: false,
        withinShutterGrace: false,
        holdLiveFeedClosed: false,
        phase: UvcFeedPhase.live,
        now: now,
      ),
      isTrue,
    );
    expect(
      uvcShouldIgnoreDisconnectEvent(
        ignoreDisconnectUntil: now.subtract(const Duration(seconds: 1)),
        initializing: false,
        openingController: false,
        reconnectInFlight: false,
        withinShutterGrace: false,
        holdLiveFeedClosed: false,
        phase: UvcFeedPhase.live,
        now: now,
      ),
      isFalse,
    );
  });

  test('uvcReconnectBackoffDelay grows then caps', () {
    expect(uvcReconnectBackoffDelay(1), const Duration(milliseconds: 650));
    expect(uvcReconnectBackoffDelay(2), const Duration(milliseconds: 1300));
    expect(uvcReconnectBackoffDelay(8), const Duration(milliseconds: 10000));
    expect(uvcReconnectBackoffDelay(20), const Duration(milliseconds: 10000));
  });

  test('uvcMayScheduleAutoReconnect respects max attempts', () {
    expect(
      uvcMayScheduleAutoReconnect(attemptCount: 0, maxAttempts: 5),
      isTrue,
    );
    expect(
      uvcMayScheduleAutoReconnect(attemptCount: 4, maxAttempts: 5),
      isTrue,
    );
    expect(
      uvcMayScheduleAutoReconnect(attemptCount: 5, maxAttempts: 5),
      isFalse,
    );
  });

  test('uvcLaterDisconnectIgnoreUntil keeps the later deadline', () {
    final later = uvcLaterDisconnectIgnoreUntil(
      current: now.add(const Duration(seconds: 1)),
      extension: const Duration(seconds: 3),
      now: now,
    );
    expect(later, now.add(const Duration(seconds: 3)));

    final unchanged = uvcLaterDisconnectIgnoreUntil(
      current: now.add(const Duration(seconds: 10)),
      extension: const Duration(seconds: 1),
      now: now,
    );
    expect(unchanged, now.add(const Duration(seconds: 10)));
  });
}
