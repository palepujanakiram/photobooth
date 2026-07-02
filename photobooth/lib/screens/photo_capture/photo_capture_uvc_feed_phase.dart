/// USB / UVC live-feed lifecycle on the capture screen.
enum UvcFeedPhase {
  /// Preview running; captures allowed.
  live,

  /// Shutter in progress — block reconnect and second captures.
  capturing,

  /// Still on screen — feed stays closed until retake.
  reviewing,

  /// Open failed; user must tap Retry (no auto-reconnect).
  error,
}

bool uvcFeedPhaseBlocksLivePreview(UvcFeedPhase phase) {
  return phase == UvcFeedPhase.capturing || phase == UvcFeedPhase.reviewing;
}

/// Whether [_resumeUvcLiveFeed] may run (retake, retry, reconnect).
bool uvcMayResumeLiveFeed({
  required UvcFeedPhase phase,
  required bool hasCapturedPhoto,
}) {
  if (hasCapturedPhoto) return false;
  return phase == UvcFeedPhase.live ||
      phase == UvcFeedPhase.error ||
      uvcFeedPhaseBlocksLivePreview(phase);
}

/// Whether the live UVC feed may auto-open (not asleep, not reviewing).
bool uvcMayAutoOpenLiveFeed({
  required UvcFeedPhase phase,
  required bool captureInFlight,
  required bool hasCapturedPhoto,
  required bool feedAsleep,
}) {
  return phase == UvcFeedPhase.live &&
      !captureInFlight &&
      !hasCapturedPhoto &&
      !feedAsleep;
}

/// Whether idle sleep may close the live UVC feed.
bool uvcIdleSleepMayCloseFeed({
  required bool idleSleepEnabled,
  required bool isUsingUvc,
  required UvcFeedPhase phase,
  required bool captureInFlight,
  required bool isCapturing,
  required bool hasCapturedPhoto,
  required bool withinShutterGrace,
  required bool feedAsleep,
}) {
  if (!idleSleepEnabled || !isUsingUvc || feedAsleep) return false;
  if (phase != UvcFeedPhase.live) return false;
  if (captureInFlight || isCapturing || hasCapturedPhoto) return false;
  if (withinShutterGrace) return false;
  return true;
}

/// Whether app lifecycle should pause (close) the UVC feed.
bool uvcLifecycleShouldPauseFeed({
  required bool lifecyclePauseEnabled,
  required bool isUsingUvc,
  required bool holdLiveFeedClosed,
  required bool hasOpenController,
}) {
  if (!lifecyclePauseEnabled || !isUsingUvc) return false;
  if (holdLiveFeedClosed) return false;
  return hasOpenController;
}

/// Whether app lifecycle resume should reopen the UVC feed.
bool uvcLifecycleShouldResumeFeed({
  required bool lifecyclePauseEnabled,
  required bool isUsingUvc,
  required bool lifecyclePaused,
  required bool mayAutoOpenLiveFeed,
  required bool blocksConcurrentAutoOpen,
  required bool withinShutterGrace,
  required bool hasOpenController,
}) {
  if (!lifecyclePauseEnabled || !isUsingUvc) return false;
  if (!lifecyclePaused) {
    return isUsingUvc &&
        !hasOpenController &&
        mayAutoOpenLiveFeed &&
        !blocksConcurrentAutoOpen &&
        !withinShutterGrace;
  }
  return mayAutoOpenLiveFeed &&
      !blocksConcurrentAutoOpen &&
      !withinShutterGrace &&
      !hasOpenController;
}

/// Block auto-open / reconnect while the feed is mid-transition.
bool uvcBlocksConcurrentAutoOpen({
  required bool initializing,
  required bool openingController,
  required UvcFeedPhase phase,
}) {
  return initializing ||
      openingController ||
      phase == UvcFeedPhase.capturing;
}

/// Whether periodic UVC session recycle may run (idle live feed only).
bool uvcSessionRecycleMayRun({
  required bool sessionRecycleEnabled,
  required bool isUsingUvc,
  required bool mayAutoOpenLiveFeed,
  required bool blocksConcurrentAutoOpen,
  required bool captureInFlight,
  required bool isCapturing,
  required bool withinShutterGrace,
}) {
  if (!sessionRecycleEnabled || !isUsingUvc) return false;
  if (!mayAutoOpenLiveFeed) return false;
  if (blocksConcurrentAutoOpen || captureInFlight || isCapturing) return false;
  if (withinShutterGrace) return false;
  return true;
}
