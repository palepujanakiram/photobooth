enum EventThemeSkipAction { showPicker, autoSelect, skipToFrames }

/// Skip the theme picker when an event is bound and there is not a real choice.
bool shouldSkipEventThemePicker({
  required String? photoMode,
  required int themeCount,
}) {
  if (photoMode == null || photoMode.trim().isEmpty) return false;
  return themeCount <= 1;
}

/// FRAME_ONLY with no assigned themes: skip theme selection entirely.
bool shouldSkipEventThemeStepForFrameOnly({
  required String? photoMode,
  required int themeCount,
}) {
  return photoMode == 'FRAME_ONLY' && themeCount <= 0;
}

EventThemeSkipAction resolveEventThemeSkipAction({
  required String? photoMode,
  required int themeCount,
}) {
  if (photoMode == null || photoMode.trim().isEmpty) {
    return EventThemeSkipAction.showPicker;
  }
  if (shouldSkipEventThemeStepForFrameOnly(
    photoMode: photoMode,
    themeCount: themeCount,
  )) {
    return EventThemeSkipAction.skipToFrames;
  }
  if (themeCount <= 0) return EventThemeSkipAction.showPicker;
  if (themeCount == 1) return EventThemeSkipAction.autoSelect;
  return EventThemeSkipAction.showPicker;
}

/// Auto-continue after themes load: one event theme plus a capture photo.
bool shouldAutoContinueEventTheme({
  required EventThemeSkipAction action,
  required bool hasCapturePhoto,
  required bool hasSelectedTheme,
}) {
  return action == EventThemeSkipAction.autoSelect &&
      hasCapturePhoto &&
      hasSelectedTheme;
}
