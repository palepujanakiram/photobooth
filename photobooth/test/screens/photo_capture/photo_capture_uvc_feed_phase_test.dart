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
}
