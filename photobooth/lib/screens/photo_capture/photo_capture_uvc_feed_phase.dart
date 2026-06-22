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
