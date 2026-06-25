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
}
