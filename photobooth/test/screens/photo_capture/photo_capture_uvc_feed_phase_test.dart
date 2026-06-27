import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_uvc_feed_phase.dart';

void main() {
  test('uvcFeedPhaseBlocksLivePreview only for capturing and reviewing', () {
    expect(uvcFeedPhaseBlocksLivePreview(UvcFeedPhase.live), isFalse);
    expect(uvcFeedPhaseBlocksLivePreview(UvcFeedPhase.capturing), isTrue);
    expect(uvcFeedPhaseBlocksLivePreview(UvcFeedPhase.reviewing), isTrue);
    expect(uvcFeedPhaseBlocksLivePreview(UvcFeedPhase.error), isFalse);
  });

  test('uvcMayResumeLiveFeed allows retake and retry paths', () {
    expect(
      uvcMayResumeLiveFeed(
        phase: UvcFeedPhase.reviewing,
        hasCapturedPhoto: false,
      ),
      isTrue,
    );
    expect(
      uvcMayResumeLiveFeed(
        phase: UvcFeedPhase.error,
        hasCapturedPhoto: false,
      ),
      isTrue,
    );
    expect(
      uvcMayResumeLiveFeed(
        phase: UvcFeedPhase.live,
        hasCapturedPhoto: true,
      ),
      isFalse,
    );
    expect(
      uvcMayResumeLiveFeed(
        phase: UvcFeedPhase.capturing,
        hasCapturedPhoto: false,
      ),
      isTrue,
    );
  });

  test('uvcBlocksConcurrentAutoOpen during init and capture', () {
    expect(
      uvcBlocksConcurrentAutoOpen(
        initializing: true,
        openingController: false,
        phase: UvcFeedPhase.live,
      ),
      isTrue,
    );
    expect(
      uvcBlocksConcurrentAutoOpen(
        initializing: false,
        openingController: true,
        phase: UvcFeedPhase.live,
      ),
      isTrue,
    );
    expect(
      uvcBlocksConcurrentAutoOpen(
        initializing: false,
        openingController: false,
        phase: UvcFeedPhase.capturing,
      ),
      isTrue,
    );
    expect(
      uvcBlocksConcurrentAutoOpen(
        initializing: false,
        openingController: false,
        phase: UvcFeedPhase.live,
      ),
      isFalse,
    );
  });

  test('uvcSessionRecycleMayRun only on idle live UVC feed', () {
    const idle = (
      sessionRecycleEnabled: true,
      isUsingUvc: true,
      mayAutoOpenLiveFeed: true,
      blocksConcurrentAutoOpen: false,
      captureInFlight: false,
      isCapturing: false,
      withinShutterGrace: false,
    );
    expect(uvcSessionRecycleMayRun(
      sessionRecycleEnabled: idle.sessionRecycleEnabled,
      isUsingUvc: idle.isUsingUvc,
      mayAutoOpenLiveFeed: idle.mayAutoOpenLiveFeed,
      blocksConcurrentAutoOpen: idle.blocksConcurrentAutoOpen,
      captureInFlight: idle.captureInFlight,
      isCapturing: idle.isCapturing,
      withinShutterGrace: idle.withinShutterGrace,
    ), isTrue);
    expect(uvcSessionRecycleMayRun(
      sessionRecycleEnabled: false,
      isUsingUvc: idle.isUsingUvc,
      mayAutoOpenLiveFeed: idle.mayAutoOpenLiveFeed,
      blocksConcurrentAutoOpen: idle.blocksConcurrentAutoOpen,
      captureInFlight: idle.captureInFlight,
      isCapturing: idle.isCapturing,
      withinShutterGrace: idle.withinShutterGrace,
    ), isFalse);
    expect(uvcSessionRecycleMayRun(
      sessionRecycleEnabled: idle.sessionRecycleEnabled,
      isUsingUvc: idle.isUsingUvc,
      mayAutoOpenLiveFeed: false,
      blocksConcurrentAutoOpen: idle.blocksConcurrentAutoOpen,
      captureInFlight: idle.captureInFlight,
      isCapturing: idle.isCapturing,
      withinShutterGrace: idle.withinShutterGrace,
    ), isFalse);
    expect(uvcSessionRecycleMayRun(
      sessionRecycleEnabled: idle.sessionRecycleEnabled,
      isUsingUvc: idle.isUsingUvc,
      mayAutoOpenLiveFeed: idle.mayAutoOpenLiveFeed,
      blocksConcurrentAutoOpen: true,
      captureInFlight: idle.captureInFlight,
      isCapturing: idle.isCapturing,
      withinShutterGrace: idle.withinShutterGrace,
    ), isFalse);
    expect(uvcSessionRecycleMayRun(
      sessionRecycleEnabled: idle.sessionRecycleEnabled,
      isUsingUvc: idle.isUsingUvc,
      mayAutoOpenLiveFeed: idle.mayAutoOpenLiveFeed,
      blocksConcurrentAutoOpen: idle.blocksConcurrentAutoOpen,
      captureInFlight: true,
      isCapturing: idle.isCapturing,
      withinShutterGrace: idle.withinShutterGrace,
    ), isFalse);
    expect(uvcSessionRecycleMayRun(
      sessionRecycleEnabled: idle.sessionRecycleEnabled,
      isUsingUvc: idle.isUsingUvc,
      mayAutoOpenLiveFeed: idle.mayAutoOpenLiveFeed,
      blocksConcurrentAutoOpen: idle.blocksConcurrentAutoOpen,
      captureInFlight: idle.captureInFlight,
      isCapturing: true,
      withinShutterGrace: idle.withinShutterGrace,
    ), isFalse);
    expect(uvcSessionRecycleMayRun(
      sessionRecycleEnabled: idle.sessionRecycleEnabled,
      isUsingUvc: idle.isUsingUvc,
      mayAutoOpenLiveFeed: idle.mayAutoOpenLiveFeed,
      blocksConcurrentAutoOpen: idle.blocksConcurrentAutoOpen,
      captureInFlight: idle.captureInFlight,
      isCapturing: idle.isCapturing,
      withinShutterGrace: true,
    ), isFalse);
  });

  test('uvcMayAutoOpenLiveFeed blocks when feed is asleep', () {
    expect(
      uvcMayAutoOpenLiveFeed(
        phase: UvcFeedPhase.live,
        captureInFlight: false,
        hasCapturedPhoto: false,
        feedAsleep: true,
      ),
      isFalse,
    );
    expect(
      uvcMayAutoOpenLiveFeed(
        phase: UvcFeedPhase.live,
        captureInFlight: false,
        hasCapturedPhoto: false,
        feedAsleep: false,
      ),
      isTrue,
    );
  });

  test('uvcIdleSleepMayCloseFeed only on idle live UVC', () {
    const ready = (
      idleSleepEnabled: true,
      isUsingUvc: true,
      phase: UvcFeedPhase.live,
      captureInFlight: false,
      isCapturing: false,
      hasCapturedPhoto: false,
      withinShutterGrace: false,
      feedAsleep: false,
    );
    expect(uvcIdleSleepMayCloseFeed(
      idleSleepEnabled: ready.idleSleepEnabled,
      isUsingUvc: ready.isUsingUvc,
      phase: ready.phase,
      captureInFlight: ready.captureInFlight,
      isCapturing: ready.isCapturing,
      hasCapturedPhoto: ready.hasCapturedPhoto,
      withinShutterGrace: ready.withinShutterGrace,
      feedAsleep: ready.feedAsleep,
    ), isTrue);
    expect(uvcIdleSleepMayCloseFeed(
      idleSleepEnabled: ready.idleSleepEnabled,
      isUsingUvc: ready.isUsingUvc,
      phase: UvcFeedPhase.reviewing,
      captureInFlight: ready.captureInFlight,
      isCapturing: ready.isCapturing,
      hasCapturedPhoto: ready.hasCapturedPhoto,
      withinShutterGrace: ready.withinShutterGrace,
      feedAsleep: ready.feedAsleep,
    ), isFalse);
    expect(uvcIdleSleepMayCloseFeed(
      idleSleepEnabled: ready.idleSleepEnabled,
      isUsingUvc: ready.isUsingUvc,
      phase: ready.phase,
      captureInFlight: ready.captureInFlight,
      isCapturing: ready.isCapturing,
      hasCapturedPhoto: ready.hasCapturedPhoto,
      withinShutterGrace: ready.withinShutterGrace,
      feedAsleep: true,
    ), isFalse);
  });

  test('uvcLifecycleShouldPauseFeed when controller is open', () {
    expect(uvcLifecycleShouldPauseFeed(
      lifecyclePauseEnabled: true,
      isUsingUvc: true,
      holdLiveFeedClosed: false,
      hasOpenController: true,
    ), isTrue);
    expect(uvcLifecycleShouldPauseFeed(
      lifecyclePauseEnabled: true,
      isUsingUvc: true,
      holdLiveFeedClosed: true,
      hasOpenController: true,
    ), isFalse);
  });

  test('uvcLifecycleShouldResumeFeed after pause or when feed closed', () {
    expect(uvcLifecycleShouldResumeFeed(
      lifecyclePauseEnabled: true,
      isUsingUvc: true,
      lifecyclePaused: true,
      mayAutoOpenLiveFeed: true,
      blocksConcurrentAutoOpen: false,
      withinShutterGrace: false,
      hasOpenController: false,
    ), isTrue);
    expect(uvcLifecycleShouldResumeFeed(
      lifecyclePauseEnabled: true,
      isUsingUvc: true,
      lifecyclePaused: false,
      mayAutoOpenLiveFeed: true,
      blocksConcurrentAutoOpen: false,
      withinShutterGrace: false,
      hasOpenController: false,
    ), isTrue);
    expect(uvcLifecycleShouldResumeFeed(
      lifecyclePauseEnabled: true,
      isUsingUvc: true,
      lifecyclePaused: false,
      mayAutoOpenLiveFeed: false,
      blocksConcurrentAutoOpen: false,
      withinShutterGrace: false,
      hasOpenController: true,
    ), isFalse);
  });
}
